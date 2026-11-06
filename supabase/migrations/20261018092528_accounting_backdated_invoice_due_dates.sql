-- Allow backlogged invoices to be issued with already-overdue due dates for receivables ageing.
-- The due date cannot predate the related booking; workspace and role checks remain enforced.
create or replace function public.issue_sales_invoice(
  p_booking_id uuid,
  p_due_date date default null,
  p_notes text default ''
) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_user_id uuid:=auth.uid();
  v_org_id uuid;
  v_b public.bookings%rowtype;
  v_invoice uuid;
  v_je uuid;
  v_ar uuid;
  v_rev uuid;
  v_cogs uuid;
  v_inventory uuid;
  v_amount numeric;
  v_cost numeric;
begin
  if v_user_id is null then raise exception 'Please sign in first.'; end if;
  select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
  if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
  if not exists(select 1 from public.memberships where organization_id=v_org_id and user_id=v_user_id and role in ('owner','admin','manager','accountant','staff')) then
    raise exception 'You do not have sales invoicing permission.';
  end if;
  select * into v_b from public.bookings where id=p_booking_id and organization_id=v_org_id for update;
  if not found then raise exception 'Booking not found in this workspace.'; end if;
  if v_b.status<>'completed' then raise exception 'Only delivered/completed bookings can be invoiced.'; end if;
  if exists(select 1 from public.sales_invoices where booking_id=v_b.id and organization_id=v_org_id) then raise exception 'This booking already has an invoice.'; end if;
  if coalesce(p_due_date,current_date+30)<v_b.booking_date then raise exception 'Invoice due date cannot be before the related booking date.'; end if;
  v_amount:=v_b.total_amount;
  v_cost:=v_b.total_cost;
  select id into v_ar from public.finance_accounts where organization_id=v_org_id and code='1100';
  select id into v_rev from public.finance_accounts where organization_id=v_org_id and code='4000';
  select id into v_cogs from public.finance_accounts where organization_id=v_org_id and code='5000';
  select id into v_inventory from public.finance_accounts where organization_id=v_org_id and code='1200';
  if v_ar is null or v_rev is null or v_cogs is null or v_inventory is null then raise exception 'Chart of accounts is not initialized. Contact your administrator.'; end if;
  insert into public.sales_invoices(organization_id,booking_id,customer_id,issue_date,due_date,subtotal,tax_amount,total_amount,notes,created_by)
  values(v_org_id,v_b.id,v_b.customer_id,current_date,coalesce(p_due_date,current_date+30),v_amount,0,v_amount,left(trim(coalesce(p_notes,'')),1000),v_user_id)
  returning id into v_invoice;
  insert into public.accounting_journal_entries(organization_id,entry_date,source_type,source_id,description,status,debit_total,credit_total,created_by,posted_by,posted_at)
  values(v_org_id,current_date,'sales_invoice',v_invoice,'Sales invoice for '||v_b.booking_no,'posted',round(v_amount+v_cost,2),round(v_amount+v_cost,2),v_user_id,v_user_id,now())
  returning id into v_je;
  insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit)
  values(v_org_id,v_je,v_ar,'Accounts receivable - '||v_b.booking_no,v_amount,0),(v_org_id,v_je,v_rev,'Sales revenue - '||v_b.booking_no,0,v_amount);
  if v_cost>0 then
    insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit)
    values(v_org_id,v_je,v_cogs,'Cost of goods sold - '||v_b.booking_no,v_cost,0),(v_org_id,v_je,v_inventory,'Inventory relieved - '||v_b.booking_no,0,v_cost);
  end if;
  update public.sales_invoices set journal_entry_id=v_je where id=v_invoice;
  return v_invoice;
end; $$;
revoke all on function public.issue_sales_invoice(uuid,date,text) from public,anon;
grant execute on function public.issue_sales_invoice(uuid,date,text) to authenticated;
