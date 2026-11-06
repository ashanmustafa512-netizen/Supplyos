-- Dispatch UX, contingencies, print manifest, truck location and geofence event tables.
-- Idempotent add-on to the preceding dispatch_module / dispatch_security_hardening migrations.
alter table public.dispatch_loads
  add column if not exists loading_status text not null default 'not_started' check (loading_status in ('not_started','loading','loaded')),
  add column if not exists loading_started_at timestamptz,
  add column if not exists loaded_at timestamptz,
  add column if not exists loading_notes text not null default '',
  add column if not exists geofence_radius_m integer not null default 250 check (geofence_radius_m between 25 and 10000);
alter table public.dispatch_trucks
  add column if not exists current_latitude numeric(10,7),
  add column if not exists current_longitude numeric(10,7),
  add column if not exists location_updated_at timestamptz;

create table if not exists public.dispatch_contingencies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  load_id uuid not null references public.dispatch_loads(id) on delete cascade,
  reported_by uuid not null references auth.users(id),
  issue_type text not null check (issue_type in ('breakdown','accident','road_closure','weather','customer_unavailable','cargo_damage','stock_discrepancy','driver_issue','delay','other')),
  severity text not null default 'medium' check (severity in ('low','medium','high','critical')),
  summary text not null check (char_length(trim(summary)) between 3 and 180),
  notes text not null default '', status text not null default 'open' check (status in ('open','resolved')),
  action_taken text not null default '', resolved_by uuid references auth.users(id), resolved_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.dispatch_bill_passes (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  load_id uuid not null references public.dispatch_loads(id) on delete cascade,
  bill_pass_no text not null default ('BP-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
  content_snapshot jsonb not null default '{}'::jsonb, issued_by uuid not null references auth.users(id),
  issued_at timestamptz not null default now(), unique (organization_id,bill_pass_no), unique (load_id)
);
create table if not exists public.dispatch_geofence_states (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  load_id uuid not null references public.dispatch_loads(id) on delete cascade,
  booking_id uuid not null references public.bookings(id) on delete cascade,
  state text not null check (state in ('inside','nearby','outside')), distance_m numeric(12,2) not null check (distance_m >= 0),
  radius_m integer not null, last_checked_at timestamptz not null default now(), unique (load_id,booking_id)
);
create table if not exists public.dispatch_geofence_events (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  load_id uuid not null references public.dispatch_loads(id) on delete cascade,
  booking_id uuid not null references public.bookings(id) on delete cascade,
  truck_id uuid not null references public.dispatch_trucks(id) on delete cascade,
  previous_state text check (previous_state in ('inside','nearby','outside')),
  new_state text not null check (new_state in ('inside','nearby','outside')),
  distance_m numeric(12,2) not null, created_at timestamptz not null default now()
);
create index if not exists dispatch_contingencies_org_status_idx on public.dispatch_contingencies(organization_id,status,severity,created_at desc);
create index if not exists dispatch_bill_passes_org_issued_idx on public.dispatch_bill_passes(organization_id,issued_at desc);
create index if not exists dispatch_geofence_states_org_load_idx on public.dispatch_geofence_states(organization_id,load_id);
create index if not exists dispatch_geofence_events_org_time_idx on public.dispatch_geofence_events(organization_id,created_at desc);

alter table public.dispatch_contingencies enable row level security;
alter table public.dispatch_bill_passes enable row level security;
alter table public.dispatch_geofence_states enable row level security;
alter table public.dispatch_geofence_events enable row level security;
revoke all on public.dispatch_contingencies,public.dispatch_bill_passes,public.dispatch_geofence_states,public.dispatch_geofence_events from anon,authenticated;
grant select on public.dispatch_contingencies,public.dispatch_bill_passes,public.dispatch_geofence_states,public.dispatch_geofence_events to authenticated;
drop policy if exists dispatch_contingencies_read_org on public.dispatch_contingencies;
create policy dispatch_contingencies_read_org on public.dispatch_contingencies for select to authenticated using (organization_id in (select m.organization_id from public.memberships m where m.user_id=(select auth.uid())));
drop policy if exists dispatch_bill_passes_read_org on public.dispatch_bill_passes;
create policy dispatch_bill_passes_read_org on public.dispatch_bill_passes for select to authenticated using (organization_id in (select m.organization_id from public.memberships m where m.user_id=(select auth.uid())));
drop policy if exists dispatch_geofence_states_read_org on public.dispatch_geofence_states;
create policy dispatch_geofence_states_read_org on public.dispatch_geofence_states for select to authenticated using (organization_id in (select m.organization_id from public.memberships m where m.user_id=(select auth.uid())));
drop policy if exists dispatch_geofence_events_read_org on public.dispatch_geofence_events;
create policy dispatch_geofence_events_read_org on public.dispatch_geofence_events for select to authenticated using (organization_id in (select m.organization_id from public.memberships m where m.user_id=(select auth.uid())));

create or replace function public.dispatch_load_action(p_load_id uuid,p_action text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid(); v_org_id uuid; v_load public.dispatch_loads%rowtype; v_booking record;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select m.organization_id into v_org_id from public.memberships m where m.user_id=v_user_id limit 1;
 if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
 select * into v_load from public.dispatch_loads where id=p_load_id and organization_id=v_org_id for update;
 if not found then raise exception 'Load not found in this workspace.'; end if;
 if p_action='start_loading' then
   if v_load.status<>'planned' then raise exception 'Only planned loads can begin loading.'; end if;
   if v_load.assigned_truck_id is null then raise exception 'Assign a truck before starting loading.'; end if;
   if v_load.loading_status='loaded' then raise exception 'This load has already been marked loaded.'; end if;
   if not exists(select 1 from public.dispatch_trucks t where t.id=v_load.assigned_truck_id and t.organization_id=v_org_id and t.status='available') then raise exception 'Assigned truck is not available. Refresh the load board and reassign it.'; end if;
   if exists(select 1 from public.dispatch_load_bookings lb join public.bookings b on b.id=lb.booking_id where lb.load_id=p_load_id and b.status<>'approved') then raise exception 'Every order on this load must still be approved.'; end if;
   update public.dispatch_loads set loading_status='loading',loading_started_at=coalesce(loading_started_at,now()),updated_at=now() where id=p_load_id;
 elsif p_action='finish_loading' then
   if v_load.status<>'planned' then raise exception 'Only a planned load can be marked loaded.'; end if;
   if v_load.assigned_truck_id is null then raise exception 'Assign a truck before completing loading.'; end if;
   if v_load.loading_status<>'loading' then raise exception 'Start loading before marking it complete.'; end if;
   if v_load.booking_count=0 or not exists(select 1 from public.dispatch_load_bookings where load_id=p_load_id) then raise exception 'This load has no linked bookings.'; end if;
   if exists(select 1 from public.dispatch_load_bookings lb join public.bookings b on b.id=lb.booking_id where lb.load_id=p_load_id and b.status<>'approved') then raise exception 'Every order on this load must still be approved.'; end if;
   update public.dispatch_loads set status='ready',loading_status='loaded',loaded_at=now(),updated_at=now() where id=p_load_id;
 elsif p_action='dispatch' then
   if v_load.status<>'ready' or v_load.loading_status<>'loaded' then raise exception 'Complete the loading checklist before dispatching this load.'; end if;
   if v_load.assigned_truck_id is null then raise exception 'Assign an available truck before dispatching.'; end if;
   update public.dispatch_trucks set status='in_transit',updated_at=now() where id=v_load.assigned_truck_id and organization_id=v_org_id and status='available' and not exists(select 1 from public.dispatch_loads x where x.assigned_truck_id=public.dispatch_trucks.id and x.id<>p_load_id and x.status not in ('delivered','cancelled'));
   if not found then raise exception 'Truck is no longer available. Refresh the load board and review its assignment.'; end if;
   update public.dispatch_loads set status='in_transit',departed_at=now(),updated_at=now() where id=p_load_id;
 elsif p_action='deliver' then
   if v_load.status<>'in_transit' then raise exception 'Only loads currently in transit can be delivered.'; end if;
   for v_booking in select b.id,b.status from public.dispatch_load_bookings lb join public.bookings b on b.id=lb.booking_id where lb.load_id=p_load_id order by lb.stop_order,b.booking_no loop
     if v_booking.status='approved' then perform public.booking_action(v_booking.id,'complete'); elsif v_booking.status<>'completed' then raise exception 'A booking on this load is not approved or completed. Resolve its booking status before closing this load.'; end if;
   end loop;
   update public.dispatch_load_bookings set delivery_status='delivered',delivered_at=now() where load_id=p_load_id;
   update public.dispatch_loads set status='delivered',delivered_at=now(),updated_at=now() where id=p_load_id;
   update public.dispatch_trucks set status='available',current_city=coalesce(nullif((v_load.stop_plan -> greatest(0,jsonb_array_length(v_load.stop_plan)-1) ->> 'city'),''),current_city),updated_at=now() where id=v_load.assigned_truck_id and organization_id=v_org_id;
 elsif p_action='cancel' then
   if v_load.status not in ('planned','ready') then raise exception 'Only loads that have not departed can be cancelled.'; end if;
   update public.dispatch_loads set status='cancelled',assigned_truck_id=null,loading_status='not_started',updated_at=now() where id=p_load_id;
 else raise exception 'Unsupported dispatch action.'; end if;
 insert into public.dispatch_events(organization_id,load_id,actor_id,action,details) values(v_org_id,p_load_id,v_user_id,p_action,jsonb_build_object('from_status',v_load.status,'to_status',case p_action when 'start_loading' then 'loading' when 'finish_loading' then 'ready' when 'dispatch' then 'in_transit' when 'deliver' then 'delivered' else 'cancelled' end));
end; $$;

create or replace function public.bulk_dispatch_loads(p_load_ids uuid[])
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid(); v_org_id uuid; v_count integer; v_id uuid;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select m.organization_id into v_org_id from public.memberships m where m.user_id=v_user_id limit 1;
 if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
 if coalesce(cardinality(p_load_ids),0)=0 then raise exception 'Select at least one ready load to dispatch.'; end if;
 if cardinality(p_load_ids)>50 then raise exception 'Bulk dispatch is limited to 50 loads per batch.'; end if;
 if (select count(distinct x) from unnest(p_load_ids) x)<>cardinality(p_load_ids) then raise exception 'Duplicate load selection detected; refresh and try again.'; end if;
 perform 1 from public.dispatch_loads l where l.id=any(p_load_ids) and l.organization_id=v_org_id order by l.id for update;
 select count(*) into v_count from public.dispatch_loads l where l.id=any(p_load_ids) and l.organization_id=v_org_id and l.status='ready' and l.loading_status='loaded' and l.assigned_truck_id is not null;
 if v_count<>cardinality(p_load_ids) then raise exception 'Every selected load must be ready, fully loaded, and assigned a truck. Nothing was dispatched.'; end if;
 if exists(select 1 from public.dispatch_loads l where l.id=any(p_load_ids) group by l.assigned_truck_id having count(*)>1) then raise exception 'A truck cannot be dispatched on two selected loads at once. Assign a separate truck to each load.'; end if;
 foreach v_id in array p_load_ids loop perform public.dispatch_load_action(v_id,'dispatch'); end loop;
 insert into public.dispatch_events(organization_id,actor_id,action,details) values(v_org_id,v_user_id,'bulk_dispatch',jsonb_build_object('load_count',cardinality(p_load_ids),'load_ids',to_jsonb(p_load_ids)));
 return jsonb_build_object('dispatched_count',cardinality(p_load_ids));
end; $$;

create or replace function public.issue_dispatch_bill_pass(p_load_id uuid)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid(); v_org_id uuid; v_load public.dispatch_loads%rowtype; v_existing uuid; v_pass_id uuid; v_snapshot jsonb;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select m.organization_id into v_org_id from public.memberships m where m.user_id=v_user_id limit 1;
 select * into v_load from public.dispatch_loads where id=p_load_id and organization_id=v_org_id for update;
 if not found then raise exception 'Load not found in this workspace.'; end if;
 if v_load.status not in ('ready','in_transit') then raise exception 'A bill pass can only be issued after loading is complete.'; end if;
 if v_load.assigned_truck_id is null then raise exception 'Assign a truck before issuing a bill pass.'; end if;
 select id into v_existing from public.dispatch_bill_passes where load_id=p_load_id;
 if v_existing is not null then return v_existing; end if;
 select jsonb_build_object('load',jsonb_build_object('id',l.id,'load_no',l.load_no,'destination_summary',l.destination_summary,'grouping_mode',l.grouping_mode,'booking_count',l.booking_count,'estimated_weight_kg',l.estimated_weight_kg,'planned_delivery_date',l.planned_delivery_date,'planned_distance_km',l.planned_distance_km,'estimated_cost',l.estimated_cost,'departed_at',l.departed_at,'created_at',l.created_at,'notes',l.notes,'stop_plan',l.stop_plan,'geofence_radius_m',l.geofence_radius_m),
 'truck',jsonb_build_object('registration_no',t.registration_no,'display_name',t.display_name,'driver_name',t.driver_name,'driver_phone',t.driver_phone,'current_city',t.current_city),
 'orders',coalesce((select jsonb_agg(jsonb_build_object('booking_no',b.booking_no,'booking_date',b.booking_date,'order_value',b.total_amount,'customer_name',c.name,'customer_code',c.customer_code,'phone',c.phone,'address',b.delivery_address,'city',b.city,'region',b.region,'province',b.province,'district',b.district,'tehsil',b.tehsil,'area',b.area,'zone',b.zone,'items',coalesce((select jsonb_agg(jsonb_build_object('name',p.name,'sku',p.sku,'quantity',bi.quantity,'unit',p.unit) order by p.name) from public.booking_items bi join public.products p on p.id=bi.product_id where bi.booking_id=b.id),'[]'::jsonb)) order by lb.stop_order,b.booking_no) from public.dispatch_load_bookings lb join public.bookings b on b.id=lb.booking_id join public.customers c on c.id=b.customer_id where lb.load_id=l.id),'[]'::jsonb),
 'notice','Dispatch manifest only. It is not a government permit or substitute for legally required transport documents.') into v_snapshot
 from public.dispatch_loads l join public.dispatch_trucks t on t.id=l.assigned_truck_id where l.id=p_load_id;
 insert into public.dispatch_bill_passes(organization_id,load_id,content_snapshot,issued_by) values(v_org_id,p_load_id,v_snapshot,v_user_id) returning id into v_pass_id;
 insert into public.dispatch_events(organization_id,load_id,actor_id,action,details) values(v_org_id,p_load_id,v_user_id,'bill_pass_issued',jsonb_build_object('bill_pass_id',v_pass_id));
 return v_pass_id;
end; $$;

create or replace function public.record_dispatch_contingency(p_load_id uuid,p_issue_type text,p_severity text,p_summary text,p_notes text default '')
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid(); v_org_id uuid; v_contingency_id uuid;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select m.organization_id into v_org_id from public.memberships m where m.user_id=v_user_id limit 1;
 if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
 if not exists(select 1 from public.dispatch_loads l where l.id=p_load_id and l.organization_id=v_org_id) then raise exception 'Choose a load from this workspace.'; end if;
 if p_issue_type not in ('breakdown','accident','road_closure','weather','customer_unavailable','cargo_damage','stock_discrepancy','driver_issue','delay','other') then raise exception 'Choose a valid contingency type.'; end if;
 if p_severity not in ('low','medium','high','critical') then raise exception 'Choose a valid severity.'; end if;
 if char_length(trim(coalesce(p_summary,'')))<3 or char_length(trim(coalesce(p_summary,'')))>180 then raise exception 'Enter a short issue summary (3–180 characters).'; end if;
 insert into public.dispatch_contingencies(organization_id,load_id,reported_by,issue_type,severity,summary,notes) values(v_org_id,p_load_id,v_user_id,p_issue_type,p_severity,trim(p_summary),left(trim(coalesce(p_notes,'')),2000)) returning id into v_contingency_id;
 insert into public.dispatch_events(organization_id,load_id,actor_id,action,details) values(v_org_id,p_load_id,v_user_id,'contingency_reported',jsonb_build_object('contingency_id',v_contingency_id,'type',p_issue_type,'severity',p_severity));
 return v_contingency_id;
end; $$;

create or replace function public.resolve_dispatch_contingency(p_contingency_id uuid,p_action_taken text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid(); v_org_id uuid;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select m.organization_id into v_org_id from public.memberships m where m.user_id=v_user_id limit 1;
 if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
 if char_length(trim(coalesce(p_action_taken,'')))<3 then raise exception 'Describe the resolution before closing this contingency.'; end if;
 update public.dispatch_contingencies c set status='resolved',action_taken=left(trim(p_action_taken),2000),resolved_by=v_user_id,resolved_at=now(),updated_at=now() where c.id=p_contingency_id and c.organization_id=v_org_id and c.status='open';
 if not found then raise exception 'Open contingency not found in this workspace.'; end if;
 insert into public.dispatch_events(organization_id,load_id,actor_id,action,details) select v_org_id,c.load_id,v_user_id,'contingency_resolved',jsonb_build_object('contingency_id',c.id,'action_taken',left(trim(p_action_taken),2000)) from public.dispatch_contingencies c where c.id=p_contingency_id;
end; $$;

create or replace function public.set_dispatch_truck_location(p_truck_id uuid,p_latitude numeric,p_longitude numeric)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid(); v_org_id uuid; v_truck public.dispatch_trucks%rowtype; v_stop record; v_distance numeric; v_state text; v_previous text; v_new_count integer:=0;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 if p_latitude is null or p_longitude is null or p_latitude < -90 or p_latitude > 90 or p_longitude < -180 or p_longitude > 180 then raise exception 'Enter valid latitude (-90 to 90) and longitude (-180 to 180).'; end if;
 select t.* into v_truck from public.dispatch_trucks t where t.id=p_truck_id and exists(select 1 from public.memberships m where m.organization_id=t.organization_id and m.user_id=v_user_id) for update;
 if not found then raise exception 'Truck not found in this workspace.'; end if;
 v_org_id:=v_truck.organization_id;
 update public.dispatch_trucks set current_latitude=p_latitude,current_longitude=p_longitude,location_updated_at=now(),updated_at=now() where id=p_truck_id and organization_id=v_org_id;
 for v_stop in select l.id as load_id,l.geofence_radius_m,b.id as booking_id,b.latitude,b.longitude from public.dispatch_loads l join public.dispatch_load_bookings lb on lb.load_id=l.id join public.bookings b on b.id=lb.booking_id where l.organization_id=v_org_id and l.assigned_truck_id=p_truck_id and l.status='in_transit' and b.latitude is not null and b.longitude is not null loop
   v_distance:=6371000*2*asin(sqrt(least(1,power(sin(radians((v_stop.latitude-p_latitude)::float8/2)),2)+cos(radians(p_latitude::float8))*cos(radians(v_stop.latitude::float8))*power(sin(radians((v_stop.longitude-p_longitude)::float8/2)),2))));
   v_state:=case when v_distance<=v_stop.geofence_radius_m then 'inside' when v_distance<=v_stop.geofence_radius_m+500 then 'nearby' else 'outside' end;
   select s.state into v_previous from public.dispatch_geofence_states s where s.load_id=v_stop.load_id and s.booking_id=v_stop.booking_id for update;
   insert into public.dispatch_geofence_states(organization_id,load_id,booking_id,state,distance_m,radius_m,last_checked_at) values(v_org_id,v_stop.load_id,v_stop.booking_id,v_state,round(v_distance,2),v_stop.geofence_radius_m,now()) on conflict(load_id,booking_id) do update set state=excluded.state,distance_m=excluded.distance_m,radius_m=excluded.radius_m,last_checked_at=now();
   if v_previous is distinct from v_state then insert into public.dispatch_geofence_events(organization_id,load_id,booking_id,truck_id,previous_state,new_state,distance_m) values(v_org_id,v_stop.load_id,v_stop.booking_id,p_truck_id,v_previous,v_state,round(v_distance,2)); v_new_count:=v_new_count+1; end if;
 end loop;
 insert into public.dispatch_events(organization_id,actor_id,action,details) values(v_org_id,v_user_id,'truck_location_updated',jsonb_build_object('truck_id',p_truck_id,'latitude',p_latitude,'longitude',p_longitude,'geofence_transitions',v_new_count));
 return jsonb_build_object('geofence_transitions',v_new_count,'location_updated_at',now());
end; $$;

revoke all on function public.bulk_dispatch_loads(uuid[]) from public,anon;
revoke all on function public.issue_dispatch_bill_pass(uuid) from public,anon;
revoke all on function public.record_dispatch_contingency(uuid,text,text,text,text) from public,anon;
revoke all on function public.resolve_dispatch_contingency(uuid,text) from public,anon;
revoke all on function public.set_dispatch_truck_location(uuid,numeric,numeric) from public,anon;
grant execute on function public.bulk_dispatch_loads(uuid[]) to authenticated;
grant execute on function public.issue_dispatch_bill_pass(uuid) to authenticated;
grant execute on function public.record_dispatch_contingency(uuid,text,text,text,text) to authenticated;
grant execute on function public.resolve_dispatch_contingency(uuid,text) to authenticated;
grant execute on function public.set_dispatch_truck_location(uuid,numeric,numeric) to authenticated;
