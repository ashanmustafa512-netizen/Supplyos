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
create or replace function public.get_my_tracking_assignments() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_user uuid:=auth.uid(); v_result jsonb;
begin
 if v_user is null then raise exception 'Please sign in first.'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('load_id',l.id,'load_no',l.load_no,'load_status',l.status,'truck_id',t.id,'registration_no',t.registration_no,'display_name',t.display_name,'driver_name',t.driver_name,'pass_status',p.status) order by l.created_at desc),'[]'::jsonb) into v_result
 from public.dispatch_truck_driver_assignments a join public.dispatch_trucks t on t.id=a.truck_id and t.organization_id=a.organization_id join public.dispatch_loads l on l.assigned_truck_id=t.id and l.organization_id=a.organization_id join public.dispatch_truck_passes p on p.load_id=l.id and p.truck_id=t.id
 where a.driver_user_id=v_user and a.active and l.status='in_transit' and p.status='cleared' and exists(select 1 from public.memberships m where m.organization_id=a.organization_id and m.user_id=v_user and m.role='staff');
 return v_result;
end; $$;
revoke all on function public.get_my_tracking_assignments() from public,anon;
grant execute on function public.get_my_tracking_assignments() to authenticated;
