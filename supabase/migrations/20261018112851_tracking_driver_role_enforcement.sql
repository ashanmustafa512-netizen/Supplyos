drop policy if exists dispatch_truck_driver_assignments_read_org on public.dispatch_truck_driver_assignments;
create policy dispatch_truck_driver_assignments_read_org on public.dispatch_truck_driver_assignments for select to authenticated using (
 organization_id in (select m.organization_id from public.memberships m where m.user_id=(select auth.uid()))
 and (driver_user_id=(select auth.uid()) or exists(select 1 from public.memberships m where m.organization_id=dispatch_truck_driver_assignments.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager','dispatcher')))
);
drop policy if exists dispatch_truck_driver_assignments_insert_org on public.dispatch_truck_driver_assignments;
create policy dispatch_truck_driver_assignments_insert_org on public.dispatch_truck_driver_assignments for insert to authenticated with check (
 exists(select 1 from public.memberships m where m.organization_id=dispatch_truck_driver_assignments.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager','dispatcher'))
 and exists(select 1 from public.dispatch_trucks t where t.id=dispatch_truck_driver_assignments.truck_id and t.organization_id=dispatch_truck_driver_assignments.organization_id)
 and exists(select 1 from public.memberships m where m.organization_id=dispatch_truck_driver_assignments.organization_id and m.user_id=dispatch_truck_driver_assignments.driver_user_id and m.role='staff')
);
drop policy if exists dispatch_truck_driver_assignments_update_org on public.dispatch_truck_driver_assignments;
create policy dispatch_truck_driver_assignments_update_org on public.dispatch_truck_driver_assignments for update to authenticated using (
 exists(select 1 from public.memberships m where m.organization_id=dispatch_truck_driver_assignments.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager','dispatcher'))
) with check (
 exists(select 1 from public.memberships m where m.organization_id=dispatch_truck_driver_assignments.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager','dispatcher'))
 and exists(select 1 from public.dispatch_trucks t where t.id=dispatch_truck_driver_assignments.truck_id and t.organization_id=dispatch_truck_driver_assignments.organization_id)
 and exists(select 1 from public.memberships m where m.organization_id=dispatch_truck_driver_assignments.organization_id and m.user_id=dispatch_truck_driver_assignments.driver_user_id and m.role='staff')
);
create or replace function public.start_dispatch_tracking_trip(p_load_id uuid,p_consent_version text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_user uuid:=auth.uid(); v_load public.dispatch_loads%rowtype; v_org uuid; v_truck public.dispatch_trucks%rowtype; v_session uuid;
begin
 if v_user is null then raise exception 'Please sign in first.'; end if;
 if coalesce(length(trim(p_consent_version)),0)<3 or length(p_consent_version)>80 then raise exception 'Trip tracking consent is required.'; end if;
 select l.* into v_load from public.dispatch_loads l where l.id=p_load_id and l.status='in_transit'
 and exists(select 1 from public.dispatch_truck_driver_assignments a where a.truck_id=l.assigned_truck_id and a.organization_id=l.organization_id and a.driver_user_id=v_user and a.active)
 and exists(select 1 from public.memberships m where m.organization_id=l.organization_id and m.user_id=v_user and m.role='staff');
 if not found then raise exception 'No active in-transit load is assigned to this driver.'; end if;
 v_org:=v_load.organization_id; select t.* into v_truck from public.dispatch_trucks t where t.id=v_load.assigned_truck_id and t.organization_id=v_org;
 if not found then raise exception 'Assigned truck could not be found.'; end if;
 if not exists(select 1 from public.dispatch_truck_passes p where p.load_id=v_load.id and p.truck_id=v_truck.id and p.status='cleared') then raise exception 'Truck inspection pass is not cleared. Tracking cannot be started for an uncleared dispatch.'; end if;
 if exists(select 1 from public.dispatch_tracking_sessions s where s.load_id=v_load.id and s.ended_at is null) or exists(select 1 from public.dispatch_tracking_sessions s where s.truck_id=v_truck.id and s.ended_at is null) then raise exception 'This load or truck already has an active tracking session.'; end if;
 insert into public.dispatch_tracking_sessions(organization_id,load_id,truck_id,driver_user_id,consent_version) values(v_org,v_load.id,v_truck.id,v_user,p_consent_version) returning id into v_session;
 insert into public.dispatch_events(organization_id,load_id,actor_id,action,details) values(v_org,v_load.id,v_user,'tracking_trip_started',jsonb_build_object('tracking_session_id',v_session,'truck_id',v_truck.id,'consent_version',p_consent_version,'consent_at',now()));
 return jsonb_build_object('session_id',v_session,'load_id',v_load.id,'truck_id',v_truck.id,'started_at',now(),'consent_version',p_consent_version);
end; $$;
create or replace function public.record_dispatch_tracking_location(p_session_id uuid,p_latitude double precision,p_longitude double precision,p_accuracy_m double precision default null,p_recorded_at timestamptz default now()) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_user uuid:=auth.uid(); v_session public.dispatch_tracking_sessions%rowtype;
begin
 if v_user is null then raise exception 'Please sign in first.'; end if;
 if p_latitude is null or p_longitude is null or p_latitude < -90 or p_latitude > 90 or p_longitude < -180 or p_longitude > 180 then raise exception 'Invalid GPS coordinates.'; end if;
 if p_accuracy_m is not null and (p_accuracy_m<0 or p_accuracy_m>10000) then raise exception 'Invalid GPS accuracy.'; end if;
 if p_recorded_at is null or p_recorded_at>now()+interval '30 seconds' or p_recorded_at<now()-interval '5 minutes' then raise exception 'GPS fix is too old or has an invalid timestamp; wait for a fresh fix.'; end if;
 select * into v_session from public.dispatch_tracking_sessions s where s.id=p_session_id and s.driver_user_id=v_user and s.ended_at is null for update;
 if not found then raise exception 'Tracking session is no longer active for this driver.'; end if;
 if not exists(select 1 from public.dispatch_loads l where l.id=v_session.load_id and l.organization_id=v_session.organization_id and l.assigned_truck_id=v_session.truck_id and l.status='in_transit') then raise exception 'Load is no longer in transit with this truck. Tracking update rejected.'; end if;
 if not exists(select 1 from public.dispatch_truck_driver_assignments a where a.truck_id=v_session.truck_id and a.organization_id=v_session.organization_id and a.driver_user_id=v_user and a.active) or not exists(select 1 from public.memberships m where m.organization_id=v_session.organization_id and m.user_id=v_user and m.role='staff') then raise exception 'Driver assignment is no longer active. Tracking update rejected.'; end if;
 perform public.set_dispatch_truck_location(v_session.truck_id,p_latitude::numeric,p_longitude::numeric);
 update public.dispatch_trucks set current_location_accuracy_m=p_accuracy_m,location_source='phone_gps' where id=v_session.truck_id and organization_id=v_session.organization_id;
 update public.dispatch_tracking_sessions set last_location_at=now() where id=v_session.id;
 return jsonb_build_object('accepted',true,'server_received_at',now(),'recorded_at',p_recorded_at,'truck_id',v_session.truck_id);
end; $$;
drop policy if exists profiles_read_workspace_members on public.profiles;
create policy profiles_read_workspace_members on public.profiles for select to authenticated using (
 exists(select 1 from public.memberships own join public.memberships peer on peer.organization_id=own.organization_id where own.user_id=(select auth.uid()) and own.role in ('owner','admin','manager','dispatcher') and peer.user_id=profiles.id)
);
revoke all on function public.stop_dispatch_tracking_for_inactive_load() from public, anon, authenticated;
revoke all on function public.stop_dispatch_tracking_when_driver_unassigned() from public, anon, authenticated;
create or replace function public.get_my_tracking_assignments() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_user uuid:=auth.uid(); v_result jsonb;
begin
 if v_user is null then raise exception 'Please sign in first.'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('load_id',l.id,'load_no',l.load_no,'load_status',l.status,'truck_id',t.id,'registration_no',t.registration_no,'display_name',t.display_name,'driver_name',t.driver_name,'pass_status',p.status) order by l.created_at desc),'[]'::jsonb) into v_result
 from public.dispatch_truck_driver_assignments a join public.dispatch_trucks t on t.id=a.truck_id and t.organization_id=a.organization_id join public.dispatch_loads l on l.assigned_truck_id=t.id and l.organization_id=a.organization_id join public.dispatch_truck_passes p on p.load_id=l.id and p.truck_id=t.id
 where a.driver_user_id=v_user and a.active and l.status='in_transit' and p.status='cleared' and exists(select 1 from public.memberships m where m.organization_id=a.organization_id and m.user_id=v_user and m.role='staff');
 return v_result;
end; $$;
revoke all on function public.get_my_tracking_assignments() from public, anon;
grant execute on function public.get_my_tracking_assignments() to authenticated;
