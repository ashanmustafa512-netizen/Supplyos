-- Restrict the recovery queue to workspace roles that work with sales/customer accounts.
alter table public.sales_recovery_tasks enable row level security;
revoke all on public.sales_recovery_tasks from anon, authenticated;
grant select on public.sales_recovery_tasks to authenticated;
drop policy if exists sales_recovery_tasks_read_org on public.sales_recovery_tasks;
create policy sales_recovery_tasks_read_org on public.sales_recovery_tasks
 for select to authenticated
 using (organization_id in (
   select m.organization_id from public.memberships m
   where m.user_id = (select auth.uid())
     and m.role in ('owner','admin','manager','accountant','staff')
 ));
revoke all on function public.create_sales_recovery_task(uuid,uuid,date,text,text,text,text) from public,anon;
revoke all on function public.update_sales_recovery_task(uuid,text,text,date) from public,anon;
grant execute on function public.create_sales_recovery_task(uuid,uuid,date,text,text,text,text) to authenticated;
grant execute on function public.update_sales_recovery_task(uuid,text,text,date) to authenticated;
