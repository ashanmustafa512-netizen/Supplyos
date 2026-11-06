-- Organization-scoped accounting summaries for accurate report KPIs and monthly trend display.
create or replace function public.finance_dashboard_summary(p_from_date date default null,p_to_date date default null)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_start date:=coalesce(p_from_date,date_trunc('month',current_date)::date);v_end date:=coalesce(p_to_date,current_date);v_result jsonb;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select m.organization_id into v_org_id from public.memberships m where m.user_id=v_user_id limit 1;
 if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
 if not exists(select 1 from public.memberships m where m.organization_id=v_org_id and m.user_id=v_user_id and m.role in ('owner','admin','manager','accountant')) then raise exception 'You do not have access to financial reporting.'; end if;
 if v_end<v_start then raise exception 'Reporting end date must not be before the start date.'; end if;
 select jsonb_build_object(
  'period_start',v_start,'period_end',v_end,
  'ledger_revenue',coalesce((select sum(jl.credit-jl.debit) from public.accounting_journal_lines jl join public.accounting_journal_entries je on je.id=jl.journal_entry_id join public.finance_accounts a on a.id=jl.account_id where je.organization_id=v_org_id and je.status='posted' and jl.organization_id=v_org_id and a.organization_id=v_org_id and a.account_type='revenue' and je.entry_date between v_start and v_end),0),
  'ledger_expenses',coalesce((select sum(jl.debit-jl.credit) from public.accounting_journal_lines jl join public.accounting_journal_entries je on je.id=jl.journal_entry_id join public.finance_accounts a on a.id=jl.account_id where je.organization_id=v_org_id and je.status='posted' and jl.organization_id=v_org_id and a.organization_id=v_org_id and a.account_type='expense' and je.entry_date between v_start and v_end),0),
  'period_invoice_sales',coalesce((select sum(i.total_amount) from public.sales_invoices i where i.organization_id=v_org_id and i.issue_date between v_start and v_end and i.status<>'void'),0),
  'period_collections',coalesce((select sum(p.amount) from public.sales_payments p where p.organization_id=v_org_id and p.payment_date between v_start and v_end),0),
  'cash_bank_movement',coalesce((select sum(jl.debit-jl.credit) from public.accounting_journal_lines jl join public.accounting_journal_entries je on je.id=jl.journal_entry_id join public.finance_accounts a on a.id=jl.account_id where je.organization_id=v_org_id and je.status='posted' and jl.organization_id=v_org_id and a.organization_id=v_org_id and a.code in ('1000','1010','1020','1030') and je.entry_date between v_start and v_end),0),
  'completed_order_value',coalesce((select sum(b.total_amount) from public.bookings b where b.organization_id=v_org_id and b.status='completed' and b.booking_date between v_start and v_end),0),
  'completed_order_cost',coalesce((select sum(b.total_cost) from public.bookings b where b.organization_id=v_org_id and b.status='completed' and b.booking_date between v_start and v_end),0),
  'open_receivables',coalesce((select sum(i.balance_due) from public.sales_invoices i where i.organization_id=v_org_id and i.status not in ('paid','void')),0),
  'supplier_payables',coalesce((select sum(jl.credit-jl.debit) from public.accounting_journal_lines jl join public.accounting_journal_entries je on je.id=jl.journal_entry_id join public.finance_accounts a on a.id=jl.account_id where je.organization_id=v_org_id and je.status='posted' and jl.organization_id=v_org_id and a.organization_id=v_org_id and a.code='2000'),0),
  'payroll_payable',coalesce((select sum(jl.credit-jl.debit) from public.accounting_journal_lines jl join public.accounting_journal_entries je on je.id=jl.journal_entry_id join public.finance_accounts a on a.id=jl.account_id where je.organization_id=v_org_id and je.status='posted' and jl.organization_id=v_org_id and a.organization_id=v_org_id and a.code='2200'),0),
  'inventory_value',coalesce((select sum(p.stock_on_hand*p.unit_cost) from public.products p where p.organization_id=v_org_id and p.is_active),0),
  'inventory_retail_value',coalesce((select sum(p.stock_on_hand*p.unit_price) from public.products p where p.organization_id=v_org_id and p.is_active),0),
  'active_employees',coalesce((select count(*) from public.employees e where e.organization_id=v_org_id and e.status='active'),0),
  'monthly_trend',coalesce((select jsonb_agg(jsonb_build_object('month',to_char(m.month_start,'YYYY-MM'),
    'revenue',coalesce((select sum(jl.credit-jl.debit) from public.accounting_journal_lines jl join public.accounting_journal_entries je on je.id=jl.journal_entry_id join public.finance_accounts a on a.id=jl.account_id where je.organization_id=v_org_id and je.status='posted' and jl.organization_id=v_org_id and a.organization_id=v_org_id and a.account_type='revenue' and je.entry_date>=m.month_start and je.entry_date<(m.month_start+interval '1 month')::date),0),
    'expenses',coalesce((select sum(jl.debit-jl.credit) from public.accounting_journal_lines jl join public.accounting_journal_entries je on je.id=jl.journal_entry_id join public.finance_accounts a on a.id=jl.account_id where je.organization_id=v_org_id and je.status='posted' and jl.organization_id=v_org_id and a.organization_id=v_org_id and a.account_type='expense' and je.entry_date>=m.month_start and je.entry_date<(m.month_start+interval '1 month')::date),0)) order by m.month_start)
   from (select generate_series(date_trunc('month',v_end)::date-interval '5 months',date_trunc('month',v_end)::date,interval '1 month')::date as month_start) m),'[]'::jsonb)
 ) into v_result;
 return v_result;
end; $$;
revoke all on function public.finance_dashboard_summary(date,date) from public,anon;
grant execute on function public.finance_dashboard_summary(date,date) to authenticated;
