do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='dispatch_trucks') then
    alter publication supabase_realtime add table public.dispatch_trucks;
  end if;
end $$;
drop policy if exists dispatch_truck_driver_assignments_manage_org on public.dispatch_truck_driver_assignments;
drop policy if exists dispatch_truck_driver_assignments_insert_org on public.dispatch_truck_driver_assignments;
drop policy if exists dispatch_truck_driver_assignments_update_org on public.dispatch_truck_driver_assignments;
drop policy if exists dispatch_truck_driver_assignments_delete_org on public.dispatch_truck_driver_assignments;
create policy dispatch_truck_driver_assignments_insert_org on public.dispatch_truck_driver_assignments for insert to authenticated with check (
 exists(select 1 from public.memberships m where m.organization_id=dispatch_truck_driver_assignments.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager','dispatcher'))
 and exists(select 1 from public.dispatch_trucks t where t.id=dispatch_truck_driver_assignments.truck_id and t.organization_id=dispatch_truck_driver_assignments.organization_id)
 and exists(select 1 from public.memberships m where m.organization_id=dispatch_truck_driver_assignments.organization_id and m.user_id=dispatch_truck_driver_assignments.driver_user_id)
);
create policy dispatch_truck_driver_assignments_update_org on public.dispatch_truck_driver_assignments for update to authenticated using (
 exists(select 1 from public.memberships m where m.organization_id=dispatch_truck_driver_assignments.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager','dispatcher'))
) with check (
 exists(select 1 from public.memberships m where m.organization_id=dispatch_truck_driver_assignments.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager','dispatcher'))
 and exists(select 1 from public.dispatch_trucks t where t.id=dispatch_truck_driver_assignments.truck_id and t.organization_id=dispatch_truck_driver_assignments.organization_id)
 and exists(select 1 from public.memberships m where m.organization_id=dispatch_truck_driver_assignments.organization_id and m.user_id=dispatch_truck_driver_assignments.driver_user_id)
);
create policy dispatch_truck_driver_assignments_delete_org on public.dispatch_truck_driver_assignments for delete to authenticated using (
 exists(select 1 from public.memberships m where m.organization_id=dispatch_truck_driver_assignments.organization_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager','dispatcher'))
);
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
 if not exists(select 1 from public.dispatch_truck_driver_assignments a where a.truck_id=v_session.truck_id and a.organization_id=v_session.organization_id and a.driver_user_id=v_user and a.active) then raise exception 'Driver assignment is no longer active. Tracking update rejected.'; end if;
 perform public.set_dispatch_truck_location(v_session.truck_id,p_latitude::numeric,p_longitude::numeric);
 update public.dispatch_trucks set current_location_accuracy_m=p_accuracy_m,location_source='phone_gps' where id=v_session.truck_id and organization_id=v_session.organization_id;
 update public.dispatch_tracking_sessions set last_location_at=now() where id=v_session.id;
 return jsonb_build_object('accepted',true,'server_received_at',now(),'recorded_at',p_recorded_at,'truck_id',v_session.truck_id);
end; $$;
create or replace function public.stop_dispatch_tracking_for_inactive_load() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
 if (new.status is distinct from old.status and new.status <> 'in_transit') or (new.assigned_truck_id is distinct from old.assigned_truck_id) then
  update public.dispatch_tracking_sessions s set ended_at=now(),stop_reason=case when new.status <> 'in_transit' then 'load_status_changed' else 'truck_assignment_changed' end where s.load_id=old.id and s.ended_at is null;
 end if;
 return new;
end; $$;
drop trigger if exists dispatch_stop_tracking_when_load_changes on public.dispatch_loads;
create trigger dispatch_stop_tracking_when_load_changes after update of status,assigned_truck_id on public.dispatch_loads for each row execute function public.stop_dispatch_tracking_for_inactive_load();
create or replace function public.stop_dispatch_tracking_when_driver_unassigned() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
 if (old.active and not new.active) or old.driver_user_id is distinct from new.driver_user_id or old.truck_id is distinct from new.truck_id then
  update public.dispatch_tracking_sessions s set ended_at=now(),stop_reason='driver_assignment_changed' where s.truck_id=old.truck_id and s.driver_user_id=old.driver_user_id and s.ended_at is null;
 end if;
 return new;
end; $$;
drop trigger if exists dispatch_stop_tracking_when_driver_unassigned on public.dispatch_truck_driver_assignments;
create trigger dispatch_stop_tracking_when_driver_unassigned after update on public.dispatch_truck_driver_assignments for each row execute function public.stop_dispatch_tracking_when_driver_unassigned();

revoke all on function public.stop_dispatch_tracking_for_inactive_load() from public, anon, authenticated;
revoke all on function public.stop_dispatch_tracking_when_driver_unassigned() from public, anon, authenticated;
