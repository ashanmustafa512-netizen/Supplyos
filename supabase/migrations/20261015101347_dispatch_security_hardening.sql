-- Dispatch security hardening and fleet management RPCs.
-- Keep mutations server-controlled; client-side table writes cannot skip lifecycle safeguards.

-- Loads, booking links, and audit events may only be mutated through transaction-safe RPCs.
revoke all on public.dispatch_trucks, public.dispatch_loads, public.dispatch_load_bookings, public.dispatch_targets, public.dispatch_events from authenticated;
grant select on public.dispatch_trucks, public.dispatch_loads, public.dispatch_load_bookings, public.dispatch_targets, public.dispatch_events to authenticated;
grant insert (organization_id, registration_no, display_name, capacity_orders, capacity_kg, cost_per_km, current_city, driver_name, driver_phone, notes) on public.dispatch_trucks to authenticated;
grant insert (organization_id, name, period_type, starts_on, ends_on, target_deliveries, target_loads, target_on_time_rate, is_active, notes, created_by) on public.dispatch_targets to authenticated;

-- These functions validate auth.uid() and workspace membership before doing their writes.
alter function public.create_dispatch_plan(uuid[], text, integer, numeric, numeric, date) security definer;
alter function public.create_dispatch_plan(uuid[], text, integer, numeric, numeric, date) set search_path to public, pg_temp;
alter function public.assign_dispatch_truck(uuid, uuid) security definer;
alter function public.assign_dispatch_truck(uuid, uuid) set search_path to public, pg_temp;
alter function public.dispatch_load_action(uuid, text) security definer;
alter function public.dispatch_load_action(uuid, text) set search_path to public, pg_temp;

-- Match each order to the exact stop hierarchy, not merely the city name.
create or replace function public.supplyos_set_dispatch_booking_stop()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare v_stop_order integer;
begin
  select coalesce(min((x.stop->>'stop_order')::integer), 1) into v_stop_order
  from public.dispatch_loads l
  join public.bookings b on b.id = new.booking_id
  cross join lateral jsonb_array_elements(l.stop_plan) as x(stop)
  where l.id = new.load_id
    and coalesce(x.stop->>'province','') = coalesce(nullif(b.province,''),'')
    and coalesce(x.stop->>'region','') = coalesce(nullif(b.region,''),'')
    and coalesce(x.stop->>'district','') = coalesce(nullif(b.district,''),'')
    and coalesce(x.stop->>'tehsil','') = coalesce(nullif(b.tehsil,''),'')
    and coalesce(x.stop->>'city','Unknown city') = coalesce(nullif(b.city,''),'Unknown city')
    and coalesce(x.stop->>'area','') = coalesce(nullif(b.area,''),'')
    and coalesce(x.stop->>'zone','') = coalesce(nullif(b.zone,''),'');
  new.stop_order := coalesce(v_stop_order, 1);
  return new;
end; $$;
drop trigger if exists dispatch_booking_exact_stop on public.dispatch_load_bookings;
create trigger dispatch_booking_exact_stop before insert on public.dispatch_load_bookings
for each row execute function public.supplyos_set_dispatch_booking_stop();
revoke all on function public.supplyos_set_dispatch_booking_stop() from public, anon, authenticated;

create or replace function public.update_dispatch_truck_status(p_truck_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_user_id uuid := auth.uid(); v_org_id uuid; v_truck public.dispatch_trucks%rowtype;
begin
  if v_user_id is null then raise exception 'Please sign in first.'; end if;
  if p_status not in ('available', 'maintenance', 'inactive') then raise exception 'Choose available, maintenance, or inactive.'; end if;
  select t.* into v_truck from public.dispatch_trucks t
  where t.id = p_truck_id and exists (select 1 from public.memberships m where m.organization_id = t.organization_id and m.user_id = v_user_id)
  for update;
  if not found then raise exception 'Truck not found in this workspace.'; end if;
  v_org_id := v_truck.organization_id;
  if v_truck.status = 'in_transit' then raise exception 'A truck in transit cannot be taken out of service.'; end if;
  if exists (select 1 from public.dispatch_loads l where l.assigned_truck_id = p_truck_id and l.organization_id = v_org_id and l.status in ('planned', 'ready', 'in_transit')) then
    raise exception 'This truck is reserved for an open load. Unassign or close that load first.';
  end if;
  update public.dispatch_trucks set status = p_status, updated_at = now() where id = p_truck_id and organization_id = v_org_id;
  insert into public.dispatch_events(organization_id, actor_id, action, details)
  values (v_org_id, v_user_id, 'truck_status_changed', jsonb_build_object('truck_id', p_truck_id, 'registration_no', v_truck.registration_no, 'from_status', v_truck.status, 'to_status', p_status));
end; $$;

create or replace function public.update_dispatch_truck_details(
  p_truck_id uuid, p_registration_no text, p_display_name text, p_capacity_orders integer,
  p_capacity_kg numeric, p_cost_per_km numeric, p_current_city text,
  p_driver_name text, p_driver_phone text, p_notes text
) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_user_id uuid := auth.uid(); v_org_id uuid; v_truck public.dispatch_trucks%rowtype;
  v_registration text := upper(trim(coalesce(p_registration_no, '')));
  v_name text := trim(coalesce(p_display_name, ''));
begin
  if v_user_id is null then raise exception 'Please sign in first.'; end if;
  if v_registration = '' or v_name = '' then raise exception 'Registration and vehicle name are required.'; end if;
  if char_length(v_registration) > 32 or char_length(v_name) > 100 then raise exception 'Vehicle name or registration is too long.'; end if;
  if p_capacity_orders is null or p_capacity_orders < 1 or p_capacity_orders > 1000 or coalesce(p_capacity_kg, -1) < 0 or coalesce(p_cost_per_km, -1) < 0 then
    raise exception 'Enter valid non-negative capacities and costs.';
  end if;
  select t.* into v_truck from public.dispatch_trucks t
  where t.id = p_truck_id and exists (select 1 from public.memberships m where m.organization_id = t.organization_id and m.user_id = v_user_id)
  for update;
  if not found then raise exception 'Truck not found in this workspace.'; end if;
  v_org_id := v_truck.organization_id;
  if v_truck.status = 'in_transit' then raise exception 'Vehicle details cannot be changed while the truck is in transit.'; end if;
  if exists (
    select 1 from public.dispatch_loads l
    where l.assigned_truck_id = p_truck_id and l.organization_id = v_org_id and l.status in ('planned', 'ready')
      and (l.booking_count > p_capacity_orders or (coalesce(p_capacity_kg, 0) > 0 and
        coalesce((select sum(bi.quantity * pr.unit_weight_kg)
                  from public.dispatch_load_bookings lb
                  join public.booking_items bi on bi.booking_id = lb.booking_id
                  join public.products pr on pr.id = bi.product_id
                  where lb.load_id = l.id), 0) > p_capacity_kg))
  ) then raise exception 'New capacity does not fit a load assigned to this truck. Increase capacity or unassign the load first.'; end if;

  update public.dispatch_trucks set registration_no = v_registration, display_name = v_name,
    capacity_orders = p_capacity_orders, capacity_kg = p_capacity_kg, cost_per_km = p_cost_per_km,
    current_city = left(trim(coalesce(p_current_city, '')), 100),
    driver_name = left(trim(coalesce(p_driver_name, '')), 120),
    driver_phone = left(trim(coalesce(p_driver_phone, '')), 40),
    notes = left(trim(coalesce(p_notes, '')), 500), updated_at = now()
  where id = p_truck_id and organization_id = v_org_id;
  update public.dispatch_loads set estimated_cost = round(planned_distance_km * p_cost_per_km, 2), updated_at = now()
    where assigned_truck_id = p_truck_id and organization_id = v_org_id and status in ('planned', 'ready');
  insert into public.dispatch_events(organization_id, actor_id, action, details)
  values (v_org_id, v_user_id, 'truck_details_updated', jsonb_build_object('truck_id', p_truck_id, 'registration_no', v_registration));
end; $$;

revoke all on function public.update_dispatch_truck_status(uuid, text) from public, anon;
revoke all on function public.update_dispatch_truck_details(uuid, text, text, integer, numeric, numeric, text, text, text, text) from public, anon;
grant execute on function public.update_dispatch_truck_status(uuid, text) to authenticated;
grant execute on function public.update_dispatch_truck_details(uuid, text, text, integer, numeric, numeric, text, text, text, text) to authenticated;
