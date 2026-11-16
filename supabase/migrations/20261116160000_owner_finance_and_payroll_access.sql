-- Keep company financial and payroll records exclusive to the Owner app.
-- Managers retain only the small cash/bank account lookup needed for sales collections.

drop policy if exists accounting_journals_read_org on public.accounting_journal_entries;
create policy accounting_journals_read_owner on public.accounting_journal_entries
for select to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = accounting_journal_entries.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin')
  )
);

drop policy if exists accounting_lines_read_org on public.accounting_journal_lines;
create policy accounting_lines_read_owner on public.accounting_journal_lines
for select to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = accounting_journal_lines.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin')
  )
);

drop policy if exists employees_read_org on public.employees;
create policy employees_read_owner on public.employees
for select to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = employees.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin')
  )
);

drop policy if exists finance_accounts_read_org on public.finance_accounts;
create policy finance_accounts_read_role_limited on public.finance_accounts
for select to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = finance_accounts.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin')
  )
  or (
    account_type = 'asset'
    and code in ('1000', '1010', '1020', '1030')
    and exists (
      select 1 from public.memberships m
      where m.organization_id = finance_accounts.organization_id
        and m.user_id = (select auth.uid())
        and m.role = 'manager'
    )
  )
  or (
    account_type = 'asset'
    and code in ('1000', '1010', '1020', '1030')
    and exists (
      select 1 from public.memberships m
      where m.organization_id = finance_accounts.organization_id
        and m.user_id = (select auth.uid())
        and m.role = 'staff'
    )
  )
);

drop policy if exists finance_expenses_read_org on public.finance_expenses;
create policy finance_expenses_read_owner on public.finance_expenses
for select to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = finance_expenses.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin')
  )
);

drop policy if exists payroll_items_read_org on public.payroll_items;
create policy payroll_items_read_owner on public.payroll_items
for select to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = payroll_items.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin')
  )
);

drop policy if exists payroll_runs_read_org on public.payroll_runs;
create policy payroll_runs_read_owner on public.payroll_runs
for select to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = payroll_runs.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin')
  )
);

-- Preserve the existing business logic in these SECURITY DEFINER functions,
-- changing only the allowed role lists. This avoids copying finance journal logic
-- into a separate migration and prevents manager/accountant bypass through RPC calls.
do $role_hardening$
declare
  v_function record;
  v_definition text;
  v_original text;
  v_updated_count integer := 0;
begin
  for v_function in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'record_finance_expense',
        'record_other_income',
        'create_manual_journal',
        'finance_dashboard_summary',
        'add_payroll_employee',
        'create_monthly_payroll_run',
        'update_payroll_item',
        'payroll_run_action',
        'update_payroll_employee'
      )
  loop
    v_definition := pg_get_functiondef(v_function.oid);
    v_original := v_definition;

    v_definition := replace(
      v_definition,
      'role in (''owner'',''admin'',''manager'',''accountant'')',
      'role in (''owner'',''admin'')'
    );
    v_definition := replace(
      v_definition,
      'role in (''owner'',''admin'',''accountant'',''manager'')',
      'role in (''owner'',''admin'')'
    );

    if v_definition = v_original then
      raise exception 'Could not apply owner-only permission hardening to function OID %.', v_function.oid;
    end if;

    execute v_definition;
    v_updated_count := v_updated_count + 1;
  end loop;

  if v_updated_count <> 9 then
    raise exception 'Expected to harden 9 finance/payroll functions; hardened %.', v_updated_count;
  end if;
end;
$role_hardening$;
