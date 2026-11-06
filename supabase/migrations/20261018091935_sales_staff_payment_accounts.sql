-- Staff can view only the asset accounts needed for receiving customer payments.
drop policy if exists finance_accounts_read_org on public.finance_accounts;
create policy finance_accounts_read_org on public.finance_accounts for select to authenticated
using (
 organization_id in (
   select m.organization_id from public.memberships m
   where m.user_id=(select auth.uid()) and m.role in ('owner','admin','manager','accountant')
 )
 or (
   account_type='asset' and code in ('1000','1010','1020','1030')
   and organization_id in (
     select m.organization_id from public.memberships m
     where m.user_id=(select auth.uid()) and m.role='staff'
   )
 )
);
