-- SupplyOS fleet visibility, single-factory geofence, pre-departure truck pass,
-- and safe route consolidation for loads that have not been sealed/marked ready.

alter table public.organizations
  add column if not exists factory_address text not null default '',
  add column if not exists factory_latitude numeric(10,7),
  add column if not exists factory_longitude numeric(10,7),
  add column if not exists factory_geofence_radius_m integer not null default 250;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'organizations_factory_coordinates_check' and conrelid = 'public.organizations'::regclass) then
    alter table public.organizations add constraint organizations_factory_coordinates_check
      check ((factory_latitude is null and factory_longitude is null) or
             (factory_latitude between -90 and 90 and factory_longitude between -180 and 180));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'organizations_factory_geofence_radius_check' and conrelid = 'public.organizations'::regclass) then
    alter table public.organizations add constraint organizations_factory_geofence_radius_check
      check (factory_geofence_radius_m between 25 and 10000);
  end if;
end $$;

alter table public.dispatch_trucks
  add column if not exists factory_distance_m numeric(12,2),
  add column if not exists factory_geofence_state text not null default 'unknown',
  add column if not exists factory_geofence_checked_at timestamptz;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'dispatch_trucks_factory_geofence_state_check' and conrelid = 'public.dispatch_trucks'::regclass) then
    alter table public.dispatch_trucks add constraint dispatch_trucks_factory_geofence_state_check
      check (factory_geofence_state in ('inside','nearby','outside','unknown'));
  end if;
end $$;

create table if not exists public.dispatch_truck_passes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  load_id uuid not null references public.dispatch_loads(id) on delete cascade,
  truck_id uuid not null references public.dispatch_trucks(id) on delete restrict,
  pass_no text not null default ('TP-' || to_char(now(),'YYYYMMDD') || '-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,6))),
  status text not null default 'inspection_pending' check (status in ('inspection_pending','cleared','hold')),
  checklist jsonb not null default '{"tyres_checked":false,"brakes_checked":false,"lights_checked":false,"mirrors_checked":false,"horn_reverse_checked":false,"fire_extinguisher_checked":false,"documents_checked":false,"cargo_secured":false}'::jsonb,
  inspection_snapshot jsonb not null default '{}'::jsonb,
  inspection_notes text not null default '',
  issued_by uuid references auth.users(id) on delete set null,
  issued_at timestamptz not null default now(),
  checked_by uuid references auth.users(id) on delete set null,
  checked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, pass_no),
  unique (load_id)
);
create index if not exists dispatch_truck_passes_org_status_idx on public.dispatch_truck_passes(organization_id,status,issued_at desc);
create index if not exists dispatch_truck_passes_truck_idx on public.dispatch_truck_passes(truck_id,issued_at desc);

alter table public.dispatch_truck_passes enable row level security;
revoke all on public.dispatch_truck_passes from anon,authenticated;
grant select on public.dispatch_truck_passes to authenticated;
drop policy if exists dispatch_truck_passes_read_org on public.dispatch_truck_passes;
create policy dispatch_truck_passes_read_org on public.dispatch_truck_passes for select to authenticated
  using (organization_id in (select m.organization_id from public.memberships m where m.user_id=(select auth.uid())));

create or replace function public.supplyos_refresh_truck_factory_geofence()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_factory record; v_distance numeric;
begin
  select o.factory_latitude,o.factory_longitude,o.factory_geofence_radius_m into v_factory
  from public.organizations o where o.id=new.organization_id;
  if new.current_latitude is null or new.current_longitude is null or v_factory.factory_latitude is null or v_factory.factory_longitude is null then
    new.factory_distance_m:=null;
    new.factory_geofence_state:='unknown';
    new.factory_geofence_checked_at:=now();
    return new;
  end if;
  v_distance:=6371000*2*asin(sqrt(least(1,
    power(sin(radians((v_factory.factory_latitude-new.current_latitude)::float8/2)),2)+
    cos(radians(new.current_latitude::float8))*cos(radians(v_factory.factory_latitude::float8))*
    power(sin(radians((v_factory.factory_longitude-new.current_longitude)::float8/2)),2))));
  new.factory_distance_m:=round(v_distance,2);
  new.factory_geofence_state:=case
    when v_distance<=v_factory.factory_geofence_radius_m then 'inside'
    when v_distance<=v_factory.factory_geofence_radius_m+500 then 'nearby'
    else 'outside' end;
  new.factory_geofence_checked_at:=now();
  return new;
end; $$;
drop trigger if exists dispatch_truck_factory_proximity on public.dispatch_trucks;
create trigger dispatch_truck_factory_proximity before insert or update of current_latitude,current_longitude,organization_id on public.dispatch_trucks
for each row execute function public.supplyos_refresh_truck_factory_geofence();
revoke all on function public.supplyos_refresh_truck_factory_geofence() from public,anon,authenticated;

create or replace function public.set_dispatch_factory_geofence(
  p_latitude numeric,p_longitude numeric,p_address text,p_radius_m integer default 250
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid(); v_org_id uuid; v_role text; v_org public.organizations%rowtype;
begin
  if v_user_id is null then raise exception 'Please sign in first.'; end if;
  select m.organization_id,m.role into v_org_id,v_role from public.memberships m where m.user_id=v_user_id limit 1;
  if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
  if v_role not in ('owner','admin','manager') then raise exception 'Only a factory owner, admin or manager can change the factory geofence.'; end if;
  if p_latitude is null or p_longitude is null or p_latitude < -90 or p_latitude > 90 or p_longitude < -180 or p_longitude > 180 then
    raise exception 'Set valid factory coordinates (latitude -90 to 90 and longitude -180 to 180).';
  end if;
  if p_radius_m is null or p_radius_m < 25 or p_radius_m > 10000 then raise exception 'Factory geofence radius must be from 25 to 10,000 metres.'; end if;
  update public.organizations set factory_latitude=p_latitude,factory_longitude=p_longitude,
    factory_address=left(trim(coalesce(p_address,'')),300),factory_geofence_radius_m=p_radius_m
  where id=v_org_id returning * into v_org;
  update public.dispatch_trucks set current_latitude=current_latitude,current_longitude=current_longitude
  where organization_id=v_org_id;
  insert into public.dispatch_events(organization_id,actor_id,action,details)
  values(v_org_id,v_user_id,'factory_geofence_updated',jsonb_build_object('latitude',p_latitude,'longitude',p_longitude,'radius_m',p_radius_m,'address',v_org.factory_address));
  return jsonb_build_object('organization_id',v_org_id,'factory_latitude',v_org.factory_latitude,'factory_longitude',v_org.factory_longitude,
    'factory_address',v_org.factory_address,'factory_geofence_radius_m',v_org.factory_geofence_radius_m);
end; $$;
revoke all on function public.set_dispatch_factory_geofence(numeric,numeric,text,integer) from public,anon;
grant execute on function public.set_dispatch_factory_geofence(numeric,numeric,text,integer) to authenticated;

create or replace function public.supplyos_truck_pass_snapshot(p_load_id uuid)
returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
  select jsonb_build_object(
    'factory',jsonb_build_object('name',o.name,'address',o.factory_address,'latitude',o.factory_latitude,'longitude',o.factory_longitude,'geofence_radius_m',o.factory_geofence_radius_m),
    'load',jsonb_build_object('id',l.id,'load_no',l.load_no,'destination_summary',l.destination_summary,'booking_count',l.booking_count,
      'estimated_weight_kg',l.estimated_weight_kg,'planned_delivery_date',l.planned_delivery_date,'planned_distance_km',l.planned_distance_km),
    'truck',jsonb_build_object('id',t.id,'registration_no',t.registration_no,'display_name',t.display_name,'driver_name',t.driver_name,
      'driver_phone',t.driver_phone,'capacity_orders',t.capacity_orders,'capacity_kg',t.capacity_kg,'current_city',t.current_city),
    'issued_at',now())
  from public.dispatch_loads l join public.dispatch_trucks t on t.id=l.assigned_truck_id
  join public.organizations o on o.id=l.organization_id where l.id=p_load_id;
$$;

create or replace function public.supplyos_auto_generate_truck_pass()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_pass_id uuid; v_snapshot jsonb;
begin
  if new.status='ready' and old.status is distinct from 'ready' and new.assigned_truck_id is not null then
    v_snapshot:=public.supplyos_truck_pass_snapshot(new.id);
    insert into public.dispatch_truck_passes(organization_id,load_id,truck_id,inspection_snapshot,issued_by)
    values(new.organization_id,new.id,new.assigned_truck_id,coalesce(v_snapshot,'{}'::jsonb),auth.uid())
    on conflict(load_id) do nothing returning id into v_pass_id;
    if v_pass_id is not null then
      insert into public.dispatch_events(organization_id,load_id,actor_id,action,details)
      values(new.organization_id,new.id,auth.uid(),'truck_pass_generated',jsonb_build_object('truck_pass_id',v_pass_id,'truck_id',new.assigned_truck_id));
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists dispatch_load_auto_truck_pass on public.dispatch_loads;
create trigger dispatch_load_auto_truck_pass after update of status on public.dispatch_loads
for each row when (new.status='ready' and old.status is distinct from 'ready') execute function public.supplyos_auto_generate_truck_pass();
revoke all on function public.supplyos_truck_pass_snapshot(uuid) from public,anon,authenticated;
revoke all on function public.supplyos_auto_generate_truck_pass() from public,anon,authenticated;

-- Existing loads that were already ready when this feature is enabled receive one pass too.
insert into public.dispatch_truck_passes(organization_id,load_id,truck_id,inspection_snapshot,issued_by)
select l.organization_id,l.id,l.assigned_truck_id,coalesce(public.supplyos_truck_pass_snapshot(l.id),'{}'::jsonb),null
from public.dispatch_loads l
where l.status in ('ready','in_transit') and l.assigned_truck_id is not null
on conflict(load_id) do nothing;

create or replace function public.supplyos_require_cleared_truck_pass()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if new.status='in_transit' and old.status is distinct from 'in_transit' then
    if new.assigned_truck_id is null or not exists(
      select 1 from public.dispatch_truck_passes p where p.load_id=new.id and p.organization_id=new.organization_id
        and p.truck_id=new.assigned_truck_id and p.status='cleared'
    ) then
      raise exception 'Complete and clear this truck’s pre-departure inspection pass before dispatching.';
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists dispatch_load_requires_truck_pass on public.dispatch_loads;
create trigger dispatch_load_requires_truck_pass before update of status on public.dispatch_loads
for each row execute function public.supplyos_require_cleared_truck_pass();
revoke all on function public.supplyos_require_cleared_truck_pass() from public,anon,authenticated;

create or replace function public.supplyos_refresh_dispatch_load_manifest(p_load_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_load public.dispatch_loads%rowtype; v_count integer; v_weight numeric; v_stops jsonb; v_summary text; v_cost numeric;
begin
  select * into v_load from public.dispatch_loads where id=p_load_id for update;
  if not found then return; end if;
  select count(*),coalesce(sum(x.weight_kg),0) into v_count,v_weight
  from (
    select lb.booking_id,coalesce(sum(bi.quantity*p.unit_weight_kg),0) weight_kg
    from public.dispatch_load_bookings lb left join public.booking_items bi on bi.booking_id=lb.booking_id
    left join public.products p on p.id=bi.product_id where lb.load_id=p_load_id group by lb.booking_id
  ) x;
  if v_count=0 then
    update public.dispatch_loads set booking_count=0,estimated_weight_kg=0,destination_summary='No bookings',stop_plan='[]'::jsonb,
      status='cancelled',assigned_truck_id=null,updated_at=now() where id=p_load_id;
    insert into public.dispatch_events(organization_id,load_id,actor_id,action,details)
    values(v_load.organization_id,p_load_id,auth.uid(),'empty_load_cancelled_after_consolidation','{}'::jsonb);
    return;
  end if;
  with stops as (
    select coalesce(nullif(b.province,''),'') province,coalesce(nullif(b.region,''),'') region,coalesce(nullif(b.district,''),'') district,
      coalesce(nullif(b.tehsil,''),'') tehsil,coalesce(nullif(b.city,''),'Unknown city') city,coalesce(nullif(b.area,''),'') area,
      coalesce(nullif(b.zone,''),'') zone,count(*) booking_count
    from public.dispatch_load_bookings lb join public.bookings b on b.id=lb.booking_id where lb.load_id=p_load_id
    group by 1,2,3,4,5,6,7
  ), ranked as (
    select row_number() over(order by province,region,district,tehsil,city,area,zone)::integer stop_order,* from stops
  )
  select coalesce(jsonb_agg(jsonb_build_object('stop_order',stop_order,'province',province,'region',region,'district',district,'tehsil',tehsil,'city',city,'area',area,'zone',zone,'booking_count',booking_count) order by stop_order),'[]'::jsonb),
    coalesce(string_agg(city,' → ' order by stop_order),'Destination not set') into v_stops,v_summary from ranked;
  select round(v_load.planned_distance_km*t.cost_per_km,2) into v_cost from public.dispatch_trucks t where t.id=v_load.assigned_truck_id;
  update public.dispatch_loads set booking_count=v_count,estimated_weight_kg=round(v_weight,3),stop_plan=v_stops,destination_summary=v_summary,
    capacity_orders=coalesce((select t.capacity_orders from public.dispatch_trucks t where t.id=v_load.assigned_truck_id),capacity_orders),
    estimated_cost=coalesce(v_cost,0),updated_at=now() where id=p_load_id;
  update public.dispatch_load_bookings lb set stop_order=coalesce((
    select min((s.stop->>'stop_order')::integer) from public.dispatch_loads l cross join lateral jsonb_array_elements(l.stop_plan) s(stop)
    join public.bookings b on b.id=lb.booking_id where l.id=p_load_id
      and coalesce(s.stop->>'province','')=coalesce(nullif(b.province,''),'')
      and coalesce(s.stop->>'region','')=coalesce(nullif(b.region,''),'')
      and coalesce(s.stop->>'district','')=coalesce(nullif(b.district,''),'')
      and coalesce(s.stop->>'tehsil','')=coalesce(nullif(b.tehsil,''),'')
      and coalesce(s.stop->>'city','Unknown city')=coalesce(nullif(b.city,''),'Unknown city')
      and coalesce(s.stop->>'area','')=coalesce(nullif(b.area,''),'')
      and coalesce(s.stop->>'zone','')=coalesce(nullif(b.zone,''),'')
  ),1) where lb.load_id=p_load_id;
end; $$;
revoke all on function public.supplyos_refresh_dispatch_load_manifest(uuid) from public,anon,authenticated;

-- Call the original transactional planner, then move compatible bookings onto existing
-- assigned trucks only if the load has not been marked ready/sealed. Coordinates are
-- preferred; city/district matching is the fallback when coordinates are absent.
create or replace function public.create_dispatch_plan_smart(
  p_booking_ids uuid[],p_grouping_mode text,p_capacity_orders integer default 10,p_capacity_kg numeric default 0,
  p_planned_distance_km numeric default 0,p_planned_delivery_date date default null
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_user_id uuid:=auth.uid(); v_org_id uuid; v_result jsonb; v_booking record; v_source record; v_target record;
  v_weight numeric; v_moved integer:=0; v_new_load_count integer:=0; v_new_assigned integer:=0; v_mode text:=lower(coalesce(p_grouping_mode,'city'));
begin
  if v_user_id is null then raise exception 'Please sign in first.'; end if;
  select m.organization_id into v_org_id from public.memberships m where m.user_id=v_user_id limit 1;
  if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;

  v_result:=public.create_dispatch_plan(p_booking_ids,p_grouping_mode,p_capacity_orders,p_capacity_kg,p_planned_distance_km,p_planned_delivery_date);

  for v_booking in
    select b.id,b.city,b.region,b.province,b.district,b.tehsil,b.area,b.zone,b.latitude,b.longitude,b.booking_no
    from public.bookings b where b.id=any(p_booking_ids) and b.organization_id=v_org_id
    order by b.province,b.region,b.district,b.tehsil,b.city,b.booking_no
  loop
    select l.id,l.created_at,l.booking_count into v_source
    from public.dispatch_load_bookings lb join public.dispatch_loads l on l.id=lb.load_id
    where lb.booking_id=v_booking.id and l.organization_id=v_org_id and l.created_at=transaction_timestamp()
    limit 1;
    if v_source.id is null then continue; end if;

    select coalesce(sum(bi.quantity*p.unit_weight_kg),0) into v_weight
    from public.booking_items bi join public.products p on p.id=bi.product_id where bi.booking_id=v_booking.id;

    select l.id,l.booking_count,l.estimated_weight_kg,l.planned_distance_km,t.id as truck_id,t.capacity_orders,t.capacity_kg,t.cost_per_km,
      case when exists(select 1 from public.dispatch_load_bookings lbx join public.bookings bx on bx.id=lbx.booking_id
        where lbx.load_id=l.id and coalesce(bx.city,'')=coalesce(v_booking.city,'') and coalesce(bx.province,'')=coalesce(v_booking.province,'')) then 0 else 1 end as route_rank
    into v_target
    from public.dispatch_loads l join public.dispatch_trucks t on t.id=l.assigned_truck_id
    where l.organization_id=v_org_id and l.created_at<transaction_timestamp() and l.status='planned'
      and l.loading_status in ('not_started','loading') and t.status='available'
      and l.assigned_truck_id is not null and l.booking_count+1<=t.capacity_orders
      and (t.capacity_kg=0 or coalesce(l.estimated_weight_kg,0)+v_weight<=t.capacity_kg)
      and exists(select 1 from public.dispatch_load_bookings lbx join public.bookings bx on bx.id=lbx.booking_id
        where lbx.load_id=l.id and (
          (coalesce(bx.city,'')=coalesce(v_booking.city,'') and coalesce(bx.province,'')=coalesce(v_booking.province,'')) or
          (nullif(coalesce(v_booking.district,''),'') is not null and bx.district=v_booking.district and bx.province=v_booking.province) or
          (v_booking.latitude is not null and v_booking.longitude is not null and bx.latitude is not null and bx.longitude is not null and
            6371000*2*asin(sqrt(least(1,power(sin(radians((bx.latitude-v_booking.latitude)::float8/2)),2)+
              cos(radians(v_booking.latitude::float8))*cos(radians(bx.latitude::float8))*power(sin(radians((bx.longitude-v_booking.longitude)::float8/2)),2))))<=25000)
        ))
      and not exists(select 1 from public.dispatch_loads other where other.assigned_truck_id=t.id and other.id<>l.id and other.status not in ('delivered','cancelled'))
    order by route_rank asc,(t.capacity_orders-l.booking_count) asc,l.created_at asc
    limit 1 for update of l,t skip locked;

    if v_target.id is not null then
      update public.dispatch_load_bookings set load_id=v_target.id where booking_id=v_booking.id and load_id=v_source.id;
      if found then
        perform public.supplyos_refresh_dispatch_load_manifest(v_source.id);
        perform public.supplyos_refresh_dispatch_load_manifest(v_target.id);
        insert into public.dispatch_events(organization_id,load_id,actor_id,action,details)
        values(v_org_id,v_target.id,v_user_id,'booking_consolidated_into_existing_route',jsonb_build_object('booking_id',v_booking.id,'source_load_id',v_source.id,'truck_id',v_target.truck_id,'reason','Compatible route and available payload/order capacity; load not sealed'));
        v_moved:=v_moved+1;
      end if;
    end if;
  end loop;

  -- Rebuild all non-empty loads created by this planning call, canceling empty shells.
  for v_source in select l.id from public.dispatch_loads l where l.organization_id=v_org_id and l.created_by=v_user_id and l.created_at=transaction_timestamp()
    and exists(select 1 from public.dispatch_load_bookings lb where lb.load_id=l.id) loop
    perform public.supplyos_refresh_dispatch_load_manifest(v_source.id);
  end loop;
  select count(*),count(*) filter(where l.assigned_truck_id is not null) into v_new_load_count,v_new_assigned
    from public.dispatch_loads l where l.organization_id=v_org_id and l.created_by=v_user_id and l.created_at=transaction_timestamp() and l.status='planned';
  return jsonb_build_object('load_count',v_new_load_count,'assigned_trucks',v_new_assigned,'booking_count',cardinality(p_booking_ids),
    'grouping_mode',v_mode,'consolidated_bookings',v_moved,'existing_routes_extended',v_moved>0);
end; $$;
revoke all on function public.create_dispatch_plan_smart(uuid[],text,integer,numeric,numeric,date) from public,anon;
grant execute on function public.create_dispatch_plan_smart(uuid[],text,integer,numeric,numeric,date) to authenticated;

create or replace function public.complete_dispatch_truck_pass(p_load_id uuid,p_checklist jsonb,p_inspection_notes text default '')
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid(); v_org_id uuid; v_pass public.dispatch_truck_passes%rowtype; v_status text;
begin
  if v_user_id is null then raise exception 'Please sign in first.'; end if;
  select m.organization_id into v_org_id from public.memberships m where m.user_id=v_user_id limit 1;
  if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
  if p_checklist is null or jsonb_typeof(p_checklist)<>'object' then raise exception 'Submit the truck inspection checklist.'; end if;
  select p.* into v_pass from public.dispatch_truck_passes p join public.dispatch_loads l on l.id=p.load_id
  where p.load_id=p_load_id and p.organization_id=v_org_id and l.status='ready' and l.assigned_truck_id=p.truck_id for update of p;
  if not found then raise exception 'Truck inspection pass not found for a ready load. Finish loading and refresh the dispatch board.'; end if;
  v_status:=case when coalesce(p_checklist->>'tyres_checked','false')='true'
    and coalesce(p_checklist->>'brakes_checked','false')='true'
    and coalesce(p_checklist->>'lights_checked','false')='true'
    and coalesce(p_checklist->>'mirrors_checked','false')='true'
    and coalesce(p_checklist->>'horn_reverse_checked','false')='true'
    and coalesce(p_checklist->>'fire_extinguisher_checked','false')='true'
    and coalesce(p_checklist->>'documents_checked','false')='true'
    and coalesce(p_checklist->>'cargo_secured','false')='true' then 'cleared' else 'hold' end;
  update public.dispatch_truck_passes set checklist=p_checklist,status=v_status,inspection_notes=left(trim(coalesce(p_inspection_notes,'')),2000),checked_by=v_user_id,checked_at=now(),updated_at=now()
  where id=v_pass.id;
  insert into public.dispatch_events(organization_id,load_id,actor_id,action,details)
  values(v_org_id,p_load_id,v_user_id,case when v_status='cleared' then 'truck_pass_cleared' else 'truck_pass_on_hold' end,
    jsonb_build_object('truck_pass_id',v_pass.id,'pass_no',v_pass.pass_no,'status',v_status,'checklist',p_checklist));
  return jsonb_build_object('id',v_pass.id,'load_id',v_pass.load_id,'truck_id',v_pass.truck_id,'pass_no',v_pass.pass_no,'status',v_status,
    'checklist',p_checklist,'inspection_notes',left(trim(coalesce(p_inspection_notes,'')),2000),'checked_by',v_user_id,'checked_at',now());
end; $$;
revoke all on function public.complete_dispatch_truck_pass(uuid,jsonb,text) from public,anon;
grant execute on function public.complete_dispatch_truck_pass(uuid,jsonb,text) to authenticated;

-- Reassignment after readiness invalidates an old vehicle check, so the new truck must be inspected.
create or replace function public.supplyos_reset_truck_pass_on_reassignment()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_snapshot jsonb;
begin
  if new.assigned_truck_id is distinct from old.assigned_truck_id then
    if new.assigned_truck_id is null then
      update public.dispatch_truck_passes set status='hold',updated_at=now() where load_id=new.id and status<>'hold';
    elsif exists(select 1 from public.dispatch_truck_passes p where p.load_id=new.id) then
      v_snapshot:=public.supplyos_truck_pass_snapshot(new.id);
      update public.dispatch_truck_passes set truck_id=new.assigned_truck_id,status='inspection_pending',
        checklist='{"tyres_checked":false,"brakes_checked":false,"lights_checked":false,"mirrors_checked":false,"horn_reverse_checked":false,"fire_extinguisher_checked":false,"documents_checked":false,"cargo_secured":false}'::jsonb,
        inspection_snapshot=coalesce(v_snapshot,'{}'::jsonb),inspection_notes='',checked_by=null,checked_at=null,updated_at=now() where load_id=new.id;
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists dispatch_load_reset_truck_pass_on_reassignment on public.dispatch_loads;
create trigger dispatch_load_reset_truck_pass_on_reassignment after update of assigned_truck_id on public.dispatch_loads
for each row when (new.assigned_truck_id is distinct from old.assigned_truck_id) execute function public.supplyos_reset_truck_pass_on_reassignment();
revoke all on function public.supplyos_reset_truck_pass_on_reassignment() from public,anon,authenticated;

-- Backfill fleet-base proximity for vehicles with a position on file.
update public.dispatch_trucks set current_latitude=current_latitude,current_longitude=current_longitude;
