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
revoke all on function public.stop_dispatch_tracking_for_inactive_load() from public,anon,authenticated;
revoke all on function public.stop_dispatch_tracking_when_driver_unassigned() from public,anon,authenticated;
