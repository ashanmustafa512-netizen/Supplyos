-- SupplyOS Dispatch module: fleet, load planning, inventory handoff, targets, and audit trail.
-- Additive migration. Existing bookings and inventory are preserved.

alter table public.customers
  add column if not exists province text not null default '',
  add column if not exists district text not null default '',
  add column if not exists tehsil text not null default '',
  add column if not exists area text not null default '',
  add column if not exists zone text not null default '',
  add column if not exists delivery_address text not null default '',
  add column if not exists latitude numeric(10,7),
  add column if not exists longitude numeric(10,7);

alter table public.bookings
  add column if not exists province text not null default '',
  add column if not exists district text not null default '',
  add column if not exists tehsil text not null default '',
  add column if not exists area text not null default '',
  add column if not exists zone text not null default '',
  add column if not exists delivery_address text not null default '',
  add column if not exists latitude numeric(10,7),
  add column if not exists longitude numeric(10,7);

alter table public.products
  add column if not exists unit_weight_kg numeric(12,3) not null default 0 check (unit_weight_kg >= 0);

-- Snapshot a customer's delivery hierarchy onto a booking when it is created.
create or replace function public.supplyos_snapshot_booking_destination()
returns trigger
language plpgsql
set search_path = public
as $$
declare v_customer public.customers%rowtype;
begin
  select * into v_customer from public.customers where id = new.customer_id;
  if found then
    new.city := coalesce(nullif(new.city, ''), v_customer.city, '');
    new.region := coalesce(nullif(new.region, ''), v_customer.region, '');
    new.province := coalesce(nullif(new.province, ''), v_customer.province, '');
    new.district := coalesce(nullif(new.district, ''), v_customer.district, '');
    new.tehsil := coalesce(nullif(new.tehsil, ''), v_customer.tehsil, '');
    new.area := coalesce(nullif(new.area, ''), v_customer.area, '');
    new.zone := coalesce(nullif(new.zone, ''), v_customer.zone, '');
    new.delivery_address := coalesce(nullif(new.delivery_address, ''), v_customer.delivery_address, '');
    new.latitude := coalesce(new.latitude, v_customer.latitude);
    new.longitude := coalesce(new.longitude, v_customer.longitude);
  end if;
  return new;
end;
$$;

drop trigger if exists bookings_snapshot_destination on public.bookings;
create trigger bookings_snapshot_destination before insert or update of customer_id on public.bookings
for each row execute function public.supplyos_snapshot_booking_destination();

update public.bookings b set
  province = coalesce(nullif(b.province, ''), c.province, ''),
  district = coalesce(nullif(b.district, ''), c.district, ''),
  tehsil = coalesce(nullif(b.tehsil, ''), c.tehsil, ''),
  area = coalesce(nullif(b.area, ''), c.area, ''),
  zone = coalesce(nullif(b.zone, ''), c.zone, ''),
  delivery_address = coalesce(nullif(b.delivery_address, ''), c.delivery_address, ''),
  latitude = coalesce(b.latitude, c.latitude),
  longitude = coalesce(b.longitude, c.longitude)
from public.customers c where c.id = b.customer_id;

-- Keep open bookings in sync when a customer's delivery profile is corrected.
create or replace function public.supplyos_sync_open_booking_destinations()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (old.city, old.region, old.province, old.district, old.tehsil, old.area, old.zone, old.delivery_address, old.latitude, old.longitude)
     is distinct from
     (new.city, new.region, new.province, new.district, new.tehsil, new.area, new.zone, new.delivery_address, new.latitude, new.longitude) then
    update public.bookings set
      city = new.city, region = new.region, province = new.province, district = new.district,
      tehsil = new.tehsil, area = new.area, zone = new.zone, delivery_address = new.delivery_address,
      latitude = new.latitude, longitude = new.longitude, updated_at = now()
    where customer_id = new.id and status in ('pending_approval', 'approved');
  end if;
  return new;
end;
$$;

drop trigger if exists customers_sync_open_booking_destinations on public.customers;
create trigger customers_sync_open_booking_destinations after update of city, region, province, district, tehsil, area, zone, delivery_address, latitude, longitude
on public.customers for each row execute function public.supplyos_sync_open_booking_destinations();

create table if not exists public.dispatch_trucks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  registration_no text not null,
  display_name text not null,
  capacity_orders integer not null default 10 check (capacity_orders between 1 and 1000),
  capacity_kg numeric(12,2) not null default 0 check (capacity_kg >= 0),
  cost_per_km numeric(14,2) not null default 0 check (cost_per_km >= 0),
  current_city text not null default '',
  driver_name text not null default '',
  driver_phone text not null default '',
  status text not null default 'available' check (status in ('available', 'in_transit', 'maintenance', 'inactive')),
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, registration_no)
);

create table if not exists public.dispatch_loads (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  load_no text not null default ('LD-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))),
  grouping_mode text not null check (grouping_mode in ('route', 'city', 'province', 'individual', 'region', 'district', 'tehsil', 'area', 'zone')),
  group_key text not null default '',
  destination_summary text not null default '',
  stop_plan jsonb not null default '[]'::jsonb,
  booking_count integer not null default 0 check (booking_count >= 0),
  capacity_orders integer not null default 10 check (capacity_orders between 1 and 1000),
  estimated_weight_kg numeric(12,3) not null default 0 check (estimated_weight_kg >= 0),
  assigned_truck_id uuid references public.dispatch_trucks(id) on delete set null,
  status text not null default 'planned' check (status in ('planned', 'ready', 'in_transit', 'delivered', 'cancelled')),
  planned_delivery_date date,
  planned_distance_km numeric(12,2) not null default 0 check (planned_distance_km >= 0),
  estimated_cost numeric(14,2) not null default 0 check (estimated_cost >= 0),
  notes text not null default '',
  created_by uuid not null references auth.users(id),
  departed_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, load_no)
);

create table if not exists public.dispatch_load_bookings (
  id uuid primary key default gen_random_uuid(),
  load_id uuid not null references public.dispatch_loads(id) on delete cascade,
  booking_id uuid not null references public.bookings(id) on delete restrict,
  stop_order integer not null default 1 check (stop_order >= 1),
  delivery_status text not null default 'pending' check (delivery_status in ('pending', 'delivered', 'issue')),
  delivery_note text not null default '',
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  unique (load_id, booking_id)
);

create table if not exists public.dispatch_targets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  period_type text not null default 'monthly' check (period_type in ('weekly', 'monthly', 'quarterly', 'annual', 'custom')),
  starts_on date not null,
  ends_on date not null,
  target_deliveries integer not null default 0 check (target_deliveries >= 0),
  target_loads integer not null default 0 check (target_loads >= 0),
  target_on_time_rate numeric(5,2) not null default 90 check (target_on_time_rate between 0 and 100),
  is_active boolean not null default true,
  notes text not null default '',
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_on >= starts_on)
);

create table if not exists public.dispatch_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  load_id uuid references public.dispatch_loads(id) on delete set null,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists dispatch_trucks_org_status_idx on public.dispatch_trucks(organization_id, status);
create index if not exists dispatch_loads_org_status_idx on public.dispatch_loads(organization_id, status, created_at desc);
create index if not exists dispatch_loads_truck_idx on public.dispatch_loads(assigned_truck_id, status);
create index if not exists dispatch_load_bookings_booking_idx on public.dispatch_load_bookings(booking_id);
create index if not exists dispatch_targets_org_period_idx on public.dispatch_targets(organization_id, is_active, starts_on, ends_on);
create index if not exists dispatch_events_org_created_idx on public.dispatch_events(organization_id, created_at desc);

alter table public.dispatch_trucks enable row level security;
alter table public.dispatch_loads enable row level security;
alter table public.dispatch_load_bookings enable row level security;
alter table public.dispatch_targets enable row level security;
alter table public.dispatch_events enable row level security;

revoke all on public.dispatch_trucks, public.dispatch_loads, public.dispatch_load_bookings, public.dispatch_targets, public.dispatch_events from anon;
revoke all on public.dispatch_trucks, public.dispatch_loads, public.dispatch_load_bookings, public.dispatch_targets, public.dispatch_events from authenticated;
grant select, insert, update on public.dispatch_trucks to authenticated;
grant select, insert, update on public.dispatch_loads to authenticated;
grant select, insert, update on public.dispatch_load_bookings to authenticated;
grant select, insert, update on public.dispatch_targets to authenticated;
grant select, insert on public.dispatch_events to authenticated;
grant insert (organization_id, customer_code, name, city, region, province, district, tehsil, area, zone, delivery_address, latitude, longitude, phone, credit_limit, score, status) on public.customers to authenticated;
grant update (customer_code, name, city, region, province, district, tehsil, area, zone, delivery_address, latitude, longitude, phone, credit_limit, score, status) on public.customers to authenticated;
grant insert (organization_id, sku, name, unit, unit_cost, unit_price, stock_on_hand, unit_weight_kg, is_active) on public.products to authenticated;
grant update (unit_weight_kg) on public.products to authenticated;

-- Org membership policies. RPCs run as invoker, so normal RLS still applies.
drop policy if exists dispatch_trucks_read_org on public.dispatch_trucks;
create policy dispatch_trucks_read_org on public.dispatch_trucks for select to authenticated using (organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid())));
drop policy if exists dispatch_trucks_insert_org on public.dispatch_trucks;
create policy dispatch_trucks_insert_org on public.dispatch_trucks for insert to authenticated with check (organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid())));
drop policy if exists dispatch_trucks_update_org on public.dispatch_trucks;
create policy dispatch_trucks_update_org on public.dispatch_trucks for update to authenticated using (organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid()))) with check (organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid())));

drop policy if exists dispatch_loads_read_org on public.dispatch_loads;
create policy dispatch_loads_read_org on public.dispatch_loads for select to authenticated using (organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid())));
drop policy if exists dispatch_loads_insert_org on public.dispatch_loads;
create policy dispatch_loads_insert_org on public.dispatch_loads for insert to authenticated with check (organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid())));
drop policy if exists dispatch_loads_update_org on public.dispatch_loads;
create policy dispatch_loads_update_org on public.dispatch_loads for update to authenticated using (organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid()))) with check (organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid())));

drop policy if exists dispatch_load_bookings_read_org on public.dispatch_load_bookings;
create policy dispatch_load_bookings_read_org on public.dispatch_load_bookings for select to authenticated using (exists (select 1 from public.dispatch_loads l where l.id = load_id and l.organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid()))));
drop policy if exists dispatch_load_bookings_insert_org on public.dispatch_load_bookings;
create policy dispatch_load_bookings_insert_org on public.dispatch_load_bookings for insert to authenticated with check (exists (select 1 from public.dispatch_loads l where l.id = load_id and l.organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid()))));
drop policy if exists dispatch_load_bookings_update_org on public.dispatch_load_bookings;
create policy dispatch_load_bookings_update_org on public.dispatch_load_bookings for update to authenticated using (exists (select 1 from public.dispatch_loads l where l.id = load_id and l.organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid())))) with check (exists (select 1 from public.dispatch_loads l where l.id = load_id and l.organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid()))));

drop policy if exists dispatch_targets_read_org on public.dispatch_targets;
create policy dispatch_targets_read_org on public.dispatch_targets for select to authenticated using (organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid())));
drop policy if exists dispatch_targets_insert_org on public.dispatch_targets;
create policy dispatch_targets_insert_org on public.dispatch_targets for insert to authenticated with check (organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid())));
drop policy if exists dispatch_targets_update_org on public.dispatch_targets;
create policy dispatch_targets_update_org on public.dispatch_targets for update to authenticated using (organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid()))) with check (organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid())));

drop policy if exists dispatch_events_read_org on public.dispatch_events;
create policy dispatch_events_read_org on public.dispatch_events for select to authenticated using (organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid())));
drop policy if exists dispatch_events_insert_org on public.dispatch_events;
create policy dispatch_events_insert_org on public.dispatch_events for insert to authenticated with check (organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid())));

-- Create draft loads from approved bookings. Route mode deliberately consolidates cities into multi-stop loads;
-- destination sorting is deterministic, not a claim of map-optimized routing.
create or replace function public.create_dispatch_plan(
  p_booking_ids uuid[],
  p_grouping_mode text,
  p_capacity_orders integer default 10,
  p_capacity_kg numeric default 0,
  p_planned_distance_km numeric default 0,
  p_planned_delivery_date date default null
)
returns jsonb
language plpgsql
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_org_id uuid;
  v_requested_count integer;
  v_valid_count integer;
  v_capacity integer := greatest(1, least(coalesce(p_capacity_orders, 10), 1000));
  v_capacity_kg numeric := greatest(0, least(coalesce(p_capacity_kg, 0), 1000000000));
  v_distance_km numeric := greatest(0, least(coalesce(p_planned_distance_km, 0), 1000000000));
  v_group record;
  v_group_ids uuid[];
  v_chunk uuid[];
  v_stops jsonb;
  v_summary text;
  v_offset integer;
  v_idx integer;
  v_stop_order integer;
  v_booking_weight numeric := 0;
  v_chunk_weight numeric := 0;
  v_truck_cost numeric := 0;
  v_load_id uuid;
  v_truck_id uuid;
  v_load_count integer := 0;
  v_assigned_count integer := 0;
  v_mode text := lower(coalesce(p_grouping_mode, 'city'));
begin
  if v_user_id is null then raise exception 'Please sign in first.'; end if;
  if v_mode not in ('route','city','province','individual','region','district','tehsil','area','zone') then raise exception 'Choose a valid grouping strategy.'; end if;
  if coalesce(cardinality(p_booking_ids), 0) = 0 then raise exception 'Select at least one approved booking.'; end if;
  if coalesce(p_capacity_kg, 0) < 0 or coalesce(p_planned_distance_km, 0) < 0 then raise exception 'Payload and distance values cannot be negative.'; end if;
  if cardinality(p_booking_ids) > 250 then raise exception 'A single planning run is limited to 250 bookings.'; end if;

  select m.organization_id into v_org_id from public.memberships m where m.user_id = v_user_id limit 1;
  if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;

  -- Serialize overlapping planning requests on the selected bookings before checking assignment.
  perform 1 from public.bookings b where b.id = any(p_booking_ids) and b.organization_id = v_org_id order by b.id for update;

  select count(distinct x) into v_requested_count from unnest(p_booking_ids) x;
  select count(*) into v_valid_count from public.bookings b where b.id = any(p_booking_ids) and b.organization_id = v_org_id and b.status = 'approved';
  if v_valid_count <> v_requested_count then raise exception 'Every selected booking must belong to this workspace and be approved.'; end if;

  if exists (
    select 1 from public.dispatch_load_bookings lb join public.dispatch_loads l on l.id = lb.load_id
    where lb.booking_id = any(p_booking_ids) and l.organization_id = v_org_id and l.status not in ('cancelled')
  ) then raise exception 'At least one selected booking is already assigned to an active or delivered load.'; end if;

  if exists (
    select 1 from (
      select bi.product_id, sum(bi.quantity) as selected_qty
      from public.booking_items bi join public.bookings b on b.id = bi.booking_id
      where b.id = any(p_booking_ids) and b.organization_id = v_org_id group by bi.product_id
    ) x join public.products p on p.id = x.product_id
    where p.organization_id = v_org_id and p.stock_reserved < x.selected_qty
  ) then raise exception 'Reserved stock does not cover the selected orders. Refresh inventory and resolve the stock warning first.'; end if;

  for v_group in
    select g.group_key from (
      select case v_mode
        when 'individual' then b.id::text
        when 'route' then 'Consolidated multi-city route'
        when 'city' then coalesce(nullif(b.city,''), 'Unknown city')
        when 'province' then coalesce(nullif(b.province,''), 'Province not set')
        when 'region' then coalesce(nullif(b.region,''), 'Region not set')
        when 'district' then coalesce(nullif(b.district,''), 'District not set')
        when 'tehsil' then coalesce(nullif(b.tehsil,''), 'Tehsil not set')
        when 'area' then coalesce(nullif(b.area,''), 'Area not set')
        when 'zone' then coalesce(nullif(b.zone,''), 'Zone not set')
      end as group_key
      from public.bookings b where b.id = any(p_booking_ids) and b.organization_id = v_org_id
    ) g group by g.group_key order by g.group_key
  loop
    select array_agg(b.id order by b.province, b.region, b.district, b.tehsil, b.city, b.area, b.zone, b.booking_no)
    into v_group_ids
    from public.bookings b where b.id = any(p_booking_ids) and b.organization_id = v_org_id
      and (case v_mode
        when 'individual' then b.id::text
        when 'route' then 'Consolidated multi-city route'
        when 'city' then coalesce(nullif(b.city,''), 'Unknown city')
        when 'province' then coalesce(nullif(b.province,''), 'Province not set')
        when 'region' then coalesce(nullif(b.region,''), 'Region not set')
        when 'district' then coalesce(nullif(b.district,''), 'District not set')
        when 'tehsil' then coalesce(nullif(b.tehsil,''), 'Tehsil not set')
        when 'area' then coalesce(nullif(b.area,''), 'Area not set')
        when 'zone' then coalesce(nullif(b.zone,''), 'Zone not set')
      end) = v_group.group_key;

    v_offset := 1;
    while v_offset <= cardinality(v_group_ids) loop
      v_chunk := array[]::uuid[];
      v_chunk_weight := 0;
      for v_idx in v_offset..cardinality(v_group_ids) loop
        select coalesce(sum(bi.quantity * p.unit_weight_kg), 0) into v_booking_weight
        from public.booking_items bi join public.products p on p.id = bi.product_id
        where bi.booking_id = v_group_ids[v_idx];
        if cardinality(v_chunk) >= v_capacity then exit; end if;
        if v_capacity_kg > 0 and cardinality(v_chunk) > 0 and v_chunk_weight + v_booking_weight > v_capacity_kg then exit; end if;
        if v_capacity_kg > 0 and cardinality(v_chunk) = 0 and v_booking_weight > v_capacity_kg then
          raise exception 'Booking % weighs % kg which exceeds the configured payload limit of % kg. Adjust product weights or plan capacity.', v_group_ids[v_idx], round(v_booking_weight, 2), v_capacity_kg;
        end if;
        v_chunk := array_append(v_chunk, v_group_ids[v_idx]);
        v_chunk_weight := v_chunk_weight + v_booking_weight;
        if cardinality(v_chunk) >= v_capacity then exit; end if;
      end loop;
      if cardinality(v_chunk) = 0 then raise exception 'Unable to create a load chunk; review order and payload capacity.'; end if;

      with stops as (
        select coalesce(nullif(b.province,''),'') province,
               coalesce(nullif(b.region,''),'') region,
               coalesce(nullif(b.district,''),'') district,
               coalesce(nullif(b.tehsil,''),'') tehsil,
               coalesce(nullif(b.city,''),'Unknown city') city,
               coalesce(nullif(b.area,''),'') area,
               coalesce(nullif(b.zone,''),'') zone,
               count(*) booking_count
        from public.bookings b where b.id = any(v_chunk)
        group by 1,2,3,4,5,6,7
      ), ranked as (
        select row_number() over(order by province, region, district, tehsil, city, area, zone)::integer stop_order, * from stops
      )
      select coalesce(jsonb_agg(jsonb_build_object('stop_order', stop_order, 'province', province, 'region', region, 'district', district, 'tehsil', tehsil, 'city', city, 'area', area, 'zone', zone, 'booking_count', booking_count) order by stop_order), '[]'::jsonb),
             coalesce(string_agg(city, ' → ' order by stop_order), 'Destination not set')
      into v_stops, v_summary from ranked;

      v_truck_id := null;
      v_truck_cost := 0;
      select t.id, t.cost_per_km into v_truck_id, v_truck_cost from public.dispatch_trucks t
      where t.organization_id = v_org_id and t.status = 'available' and t.capacity_orders >= cardinality(v_chunk)
        and (t.capacity_kg = 0 or t.capacity_kg >= v_chunk_weight)
        and not exists (select 1 from public.dispatch_loads l where l.assigned_truck_id = t.id and l.status not in ('delivered','cancelled'))
      order by case when t.capacity_kg > 0 then 0 else 1 end, t.capacity_orders asc, t.created_at asc limit 1 for update skip locked;

      insert into public.dispatch_loads (organization_id, grouping_mode, group_key, destination_summary, stop_plan,
        booking_count, capacity_orders, estimated_weight_kg, assigned_truck_id, status, planned_delivery_date, planned_distance_km, estimated_cost, created_by)
      values (v_org_id, v_mode, v_group.group_key, v_summary, v_stops, cardinality(v_chunk), v_capacity, round(v_chunk_weight,3), v_truck_id,
        'planned', p_planned_delivery_date, v_distance_km, case when v_truck_id is not null then round(v_distance_km * v_truck_cost, 2) else 0 end, v_user_id)
      returning id into v_load_id;

      for v_stop_order in 1..cardinality(v_chunk) loop
        -- Per-booking stop number references the deterministic city-order in the load's stop plan.
        insert into public.dispatch_load_bookings(load_id, booking_id, stop_order)
        select v_load_id, b.id,
          (select coalesce(min((s->>'stop_order')::integer), 1) from jsonb_array_elements(v_stops) as x(stop) where coalesce(x.stop->>'city','') = coalesce(nullif(b.city,''),'Unknown city'))
        from public.bookings b where b.id = v_chunk[v_stop_order];
      end loop;

      insert into public.dispatch_events(organization_id, load_id, actor_id, action, details)
      values (v_org_id, v_load_id, v_user_id, 'planned', jsonb_build_object('grouping_mode', v_mode, 'booking_count', cardinality(v_chunk), 'capacity_orders', v_capacity, 'truck_assigned', v_truck_id is not null));

      v_load_count := v_load_count + 1;
      if v_truck_id is not null then v_assigned_count := v_assigned_count + 1; end if;
      v_offset := v_offset + cardinality(v_chunk);
    end loop;
  end loop;

  return jsonb_build_object('load_count', v_load_count, 'assigned_trucks', v_assigned_count, 'booking_count', v_requested_count, 'grouping_mode', v_mode);
end;
$$;

create or replace function public.assign_dispatch_truck(p_load_id uuid, p_truck_id uuid)
returns void
language plpgsql
set search_path = public
as $$
declare v_user_id uuid := auth.uid(); v_org_id uuid; v_load public.dispatch_loads%rowtype; v_truck public.dispatch_trucks%rowtype; v_weight numeric := 0;
begin
  if v_user_id is null then raise exception 'Please sign in first.'; end if;
  select m.organization_id into v_org_id from public.memberships m where m.user_id = v_user_id limit 1;
  select * into v_load from public.dispatch_loads where id = p_load_id and organization_id = v_org_id for update;
  if not found then raise exception 'Load not found in this workspace.'; end if;
  if v_load.status not in ('planned','ready') then raise exception 'Truck can only be reassigned before the load departs.'; end if;
  if p_truck_id is null then
    update public.dispatch_loads set assigned_truck_id = null, estimated_cost = 0, updated_at = now() where id = p_load_id;
    insert into public.dispatch_events(organization_id, load_id, actor_id, action, details) values (v_org_id, p_load_id, v_user_id, 'truck_unassigned', '{}'::jsonb);
    return;
  end if;
  select * into v_truck from public.dispatch_trucks where id = p_truck_id and organization_id = v_org_id for update;
  if not found then raise exception 'Choose a truck from this workspace.'; end if;
  if v_truck.status <> 'available' then raise exception 'Selected truck is not available.'; end if;
  if v_truck.capacity_orders < v_load.booking_count then raise exception 'Selected truck does not have enough order capacity for this load.'; end if;
  select coalesce(sum(bi.quantity * p.unit_weight_kg), 0) into v_weight from public.dispatch_load_bookings lb join public.booking_items bi on bi.booking_id = lb.booking_id join public.products p on p.id = bi.product_id where lb.load_id = p_load_id;
  if v_truck.capacity_kg > 0 and v_weight > v_truck.capacity_kg then raise exception 'This load weighs % kg, above the selected truck payload capacity of % kg.', round(v_weight,2), v_truck.capacity_kg; end if;
  if exists (select 1 from public.dispatch_loads l where l.assigned_truck_id = p_truck_id and l.id <> p_load_id and l.status not in ('delivered','cancelled')) then
    raise exception 'This truck is already reserved for another open load.';
  end if;
  update public.dispatch_loads set assigned_truck_id = p_truck_id, estimated_weight_kg = round(v_weight,3), estimated_cost = round(v_load.planned_distance_km * v_truck.cost_per_km, 2), updated_at = now() where id = p_load_id;
  insert into public.dispatch_events(organization_id, load_id, actor_id, action, details) values (v_org_id, p_load_id, v_user_id, 'truck_assigned', jsonb_build_object('truck_id', p_truck_id, 'registration_no', v_truck.registration_no));
end;
$$;

create or replace function public.dispatch_load_action(p_load_id uuid, p_action text)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid(); v_org_id uuid; v_load public.dispatch_loads%rowtype; v_booking record;
begin
  if v_user_id is null then raise exception 'Please sign in first.'; end if;
  select m.organization_id into v_org_id from public.memberships m where m.user_id = v_user_id limit 1;
  if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
  select * into v_load from public.dispatch_loads where id = p_load_id and organization_id = v_org_id for update;
  if not found then raise exception 'Load not found in this workspace.'; end if;

  if p_action = 'dispatch' then
    if v_load.status not in ('planned','ready') then raise exception 'Only planned loads can depart.'; end if;
    if v_load.assigned_truck_id is null then raise exception 'Assign an available truck before dispatching.'; end if;
    if v_load.booking_count = 0 then raise exception 'A load must contain at least one booking.'; end if;
    update public.dispatch_trucks set status = 'in_transit', updated_at = now()
      where id = v_load.assigned_truck_id and organization_id = v_org_id and status = 'available';
    if not found then raise exception 'Truck is not available anymore. Refresh the load board.'; end if;
    update public.dispatch_loads set status = 'in_transit', departed_at = now(), updated_at = now() where id = p_load_id;

  elsif p_action = 'deliver' then
    if v_load.status <> 'in_transit' then raise exception 'Only loads currently in transit can be delivered.'; end if;
    for v_booking in select b.id, b.status from public.dispatch_load_bookings lb join public.bookings b on b.id = lb.booking_id where lb.load_id = p_load_id order by lb.stop_order, b.booking_no loop
      if v_booking.status = 'approved' then
        perform public.booking_action(v_booking.id, 'complete');
      elsif v_booking.status <> 'completed' then
        raise exception 'Booking % is not approved/completed. Resolve its booking status before closing this load.', v_booking.id;
      end if;
    end loop;
    update public.dispatch_load_bookings set delivery_status = 'delivered', delivered_at = now() where load_id = p_load_id;
    update public.dispatch_loads set status = 'delivered', delivered_at = now(), updated_at = now() where id = p_load_id;
    update public.dispatch_trucks set status = 'available', current_city = coalesce(nullif((v_load.stop_plan -> greatest(0, jsonb_array_length(v_load.stop_plan) - 1) ->> 'city'), ''), current_city), updated_at = now() where id = v_load.assigned_truck_id and organization_id = v_org_id;

  elsif p_action = 'cancel' then
    if v_load.status not in ('planned','ready') then raise exception 'Only loads that have not departed can be cancelled.'; end if;
    update public.dispatch_loads set status = 'cancelled', assigned_truck_id = null, updated_at = now() where id = p_load_id;

  else
    raise exception 'Unsupported dispatch action.';
  end if;

  insert into public.dispatch_events(organization_id, load_id, actor_id, action, details)
  values (v_org_id, p_load_id, v_user_id, p_action, jsonb_build_object('from_status', v_load.status, 'to_status', case p_action when 'dispatch' then 'in_transit' when 'deliver' then 'delivered' else 'cancelled' end));
end;
$$;

revoke all on function public.supplyos_snapshot_booking_destination() from public, anon, authenticated;
revoke all on function public.supplyos_sync_open_booking_destinations() from public, anon, authenticated;
revoke all on function public.create_dispatch_plan(uuid[], text, integer, numeric, numeric, date) from public, anon;
revoke all on function public.assign_dispatch_truck(uuid, uuid) from public, anon;
revoke all on function public.dispatch_load_action(uuid, text) from public, anon;
grant execute on function public.create_dispatch_plan(uuid[], text, integer, numeric, numeric, date) to authenticated;
grant execute on function public.assign_dispatch_truck(uuid, uuid) to authenticated;
grant execute on function public.dispatch_load_action(uuid, text) to authenticated;
