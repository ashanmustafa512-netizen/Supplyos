-- Sales invoicing, collections, expense/income posting, and balanced manual journals.
create or replace function public.issue_sales_invoice(p_booking_id uuid,p_due_date date default null,p_notes text default '')
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_b public.bookings%rowtype;v_invoice uuid;v_je uuid;v_ar uuid;v_rev uuid;v_cogs uuid;v_inventory uuid;v_amount numeric;v_cost numeric;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
 if not exists(select 1 from public.memberships where organization_id=v_org_id and user_id=v_user_id and role in ('owner','admin','manager','accountant','staff')) then raise exception 'You do not have sales invoicing permission.'; end if;
 select * into v_b from public.bookings where id=p_booking_id and organization_id=v_org_id for update;
 if not found then raise exception 'Booking not found in this workspace.'; end if;
 if v_b.status<>'completed' then raise exception 'Only delivered/completed bookings can be invoiced.'; end if;
 if exists(select 1 from public.sales_invoices where booking_id=v_b.id and organization_id=v_org_id) then raise exception 'This booking already has an invoice.'; end if;
 if coalesce(p_due_date,current_date+30)<current_date then raise exception 'Invoice due date cannot be before today.'; end if;
 v_amount:=v_b.total_amount;v_cost:=v_b.total_cost;
 select id into v_ar from public.finance_accounts where organization_id=v_org_id and code='1100';
 select id into v_rev from public.finance_accounts where organization_id=v_org_id and code='4000';
 select id into v_cogs from public.finance_accounts where organization_id=v_org_id and code='5000';
 select id into v_inventory from public.finance_accounts where organization_id=v_org_id and code='1200';
 if v_ar is null or v_rev is null or v_cogs is null or v_inventory is null then raise exception 'Chart of accounts is not initialized. Contact your administrator.'; end if;
 insert into public.sales_invoices(organization_id,booking_id,customer_id,issue_date,due_date,subtotal,tax_amount,total_amount,notes,created_by)
 values(v_org_id,v_b.id,v_b.customer_id,current_date,coalesce(p_due_date,current_date+30),v_amount,0,v_amount,left(trim(coalesce(p_notes,'')),1000),v_user_id) returning id into v_invoice;
 insert into public.accounting_journal_entries(organization_id,entry_date,source_type,source_id,description,status,debit_total,credit_total,created_by,posted_by,posted_at)
 values(v_org_id,current_date,'sales_invoice',v_invoice,'Sales invoice for '||v_b.booking_no,'posted',round(v_amount+v_cost,2),round(v_amount+v_cost,2),v_user_id,v_user_id,now()) returning id into v_je;
 insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit)
 values(v_org_id,v_je,v_ar,'Accounts receivable - '||v_b.booking_no,v_amount,0),(v_org_id,v_je,v_rev,'Sales revenue - '||v_b.booking_no,0,v_amount);
 if v_cost>0 then
  insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit)
  values(v_org_id,v_je,v_cogs,'Cost of goods sold - '||v_b.booking_no,v_cost,0),(v_org_id,v_je,v_inventory,'Inventory relieved - '||v_b.booking_no,0,v_cost);
 end if;
 update public.sales_invoices set journal_entry_id=v_je where id=v_invoice;
 return v_invoice;
end; $$;

create or replace function public.record_sales_payment(p_invoice_id uuid,p_payment_date date,p_amount numeric,p_payment_method text,p_reference text,p_received_account_code text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_invoice public.sales_invoices%rowtype;v_account uuid;v_ar uuid;v_payment uuid;v_je uuid;v_remaining numeric;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
 if not exists(select 1 from public.memberships where organization_id=v_org_id and user_id=v_user_id and role in ('owner','admin','manager','accountant','staff')) then raise exception 'You do not have receivables permission.'; end if;
 select * into v_invoice from public.sales_invoices where id=p_invoice_id and organization_id=v_org_id for update;
 if not found or v_invoice.status='void' then raise exception 'Open invoice not found.'; end if;
 if p_amount is null or p_amount<=0 then raise exception 'Payment amount must be greater than zero.'; end if;
 v_remaining:=v_invoice.total_amount-v_invoice.amount_paid;
 if p_amount>v_remaining then raise exception 'Payment is greater than the remaining invoice balance (%).',round(v_remaining,2); end if;
 if p_payment_method not in ('cash','bank_transfer','cheque','card','other') then raise exception 'Choose a valid payment method.'; end if;
 select id into v_account from public.finance_accounts where organization_id=v_org_id and code=trim(p_received_account_code) and account_type='asset' and is_active;
 if v_account is null then raise exception 'Choose an active cash or bank account.'; end if;
 select id into v_ar from public.finance_accounts where organization_id=v_org_id and code='1100';
 insert into public.sales_payments(organization_id,invoice_id,customer_id,payment_date,amount,payment_method,reference,received_into_account_id,created_by)
 values(v_org_id,v_invoice.id,v_invoice.customer_id,coalesce(p_payment_date,current_date),p_amount,p_payment_method,left(trim(coalesce(p_reference,'')),150),v_account,v_user_id) returning id into v_payment;
 insert into public.accounting_journal_entries(organization_id,entry_date,source_type,source_id,description,status,debit_total,credit_total,created_by,posted_by,posted_at)
 values(v_org_id,coalesce(p_payment_date,current_date),'customer_payment',v_payment,'Customer payment for '||v_invoice.invoice_no,'posted',p_amount,p_amount,v_user_id,v_user_id,now()) returning id into v_je;
 insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit)
 values(v_org_id,v_je,v_account,'Payment received: '||v_invoice.invoice_no,p_amount,0),(v_org_id,v_je,v_ar,'Receivable settled: '||v_invoice.invoice_no,0,p_amount);
 insert into public.sales_payment_allocations(organization_id,payment_id,invoice_id,amount) values(v_org_id,v_payment,v_invoice.id,p_amount);
 update public.sales_payments set journal_entry_id=v_je where id=v_payment;
 update public.sales_invoices set amount_paid=amount_paid+p_amount,status=case when amount_paid+p_amount>=total_amount then 'paid' else 'partial' end where id=v_invoice.id;
 update public.customers set credit_used=greatest(0,credit_used-p_amount) where id=v_invoice.customer_id and organization_id=v_org_id;
 return v_payment;
end; $$;

create or replace function public.record_finance_expense(p_date date,p_expense_account_code text,p_paid_from_account_code text,p_amount numeric,p_description text,p_vendor text default '',p_payment_method text default 'bank_transfer',p_reference text default '')
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_expense_acc uuid;v_cash_acc uuid;v_id uuid;v_je uuid;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 if not exists(select 1 from public.memberships where organization_id=v_org_id and user_id=v_user_id and role in ('owner','admin','accountant','manager')) then raise exception 'You do not have accounting permission.'; end if;
 if p_amount is null or p_amount<=0 or nullif(trim(p_description),'') is null then raise exception 'Enter a positive amount and description.'; end if;
 if p_payment_method not in ('cash','bank_transfer','cheque','card','other') then raise exception 'Choose a valid payment method.'; end if;
 select id into v_expense_acc from public.finance_accounts where organization_id=v_org_id and code=trim(p_expense_account_code) and account_type='expense' and is_active;
 select id into v_cash_acc from public.finance_accounts where organization_id=v_org_id and code=trim(p_paid_from_account_code) and account_type='asset' and is_active;
 if v_expense_acc is null or v_cash_acc is null then raise exception 'Select a valid expense category and cash/bank account.'; end if;
 insert into public.finance_expenses(organization_id,expense_date,expense_account_id,paid_from_account_id,vendor,description,amount,payment_method,reference,created_by)
 values(v_org_id,coalesce(p_date,current_date),v_expense_acc,v_cash_acc,left(trim(coalesce(p_vendor,'')),160),trim(p_description),p_amount,p_payment_method,left(trim(coalesce(p_reference,'')),150),v_user_id) returning id into v_id;
 insert into public.accounting_journal_entries(organization_id,entry_date,source_type,source_id,description,status,debit_total,credit_total,created_by,posted_by,posted_at)
 values(v_org_id,coalesce(p_date,current_date),'expense',v_id,trim(p_description),'posted',p_amount,p_amount,v_user_id,v_user_id,now()) returning id into v_je;
 insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit)
 values(v_org_id,v_je,v_expense_acc,trim(p_description),p_amount,0),(v_org_id,v_je,v_cash_acc,'Paid: '||trim(p_description),0,p_amount);
 update public.finance_expenses set journal_entry_id=v_je where id=v_id;
 return v_id;
end; $$;

create or replace function public.record_other_income(p_date date,p_received_account_code text,p_amount numeric,p_description text,p_reference text default '')
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_cash_acc uuid;v_income_acc uuid;v_je uuid;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 if not exists(select 1 from public.memberships where organization_id=v_org_id and user_id=v_user_id and role in ('owner','admin','accountant','manager')) then raise exception 'You do not have accounting permission.'; end if;
 if p_amount is null or p_amount<=0 or nullif(trim(p_description),'') is null then raise exception 'Enter a positive amount and description.'; end if;
 select id into v_cash_acc from public.finance_accounts where organization_id=v_org_id and code=trim(p_received_account_code) and account_type='asset' and is_active;
 select id into v_income_acc from public.finance_accounts where organization_id=v_org_id and code='4100';
 if v_cash_acc is null then raise exception 'Choose a valid cash or bank account.'; end if;
 insert into public.accounting_journal_entries(organization_id,entry_date,source_type,description,status,debit_total,credit_total,created_by,posted_by,posted_at)
 values(v_org_id,coalesce(p_date,current_date),'other_income',trim(p_description),'posted',p_amount,p_amount,v_user_id,v_user_id,now()) returning id into v_je;
 insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit)
 values(v_org_id,v_je,v_cash_acc,trim(p_description),p_amount,0),(v_org_id,v_je,v_income_acc,'Other income: '||trim(p_description),0,p_amount);
 return v_je;
end; $$;

create or replace function public.create_manual_journal(p_date date,p_description text,p_lines jsonb)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_debit numeric;v_credit numeric;v_je uuid;v_count integer;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 if not exists(select 1 from public.memberships where organization_id=v_org_id and user_id=v_user_id and role in ('owner','admin','accountant')) then raise exception 'Only accounting administrators can post manual journals.'; end if;
 if nullif(trim(p_description),'') is null or jsonb_typeof(p_lines)<>'array' then raise exception 'Journal description and lines are required.'; end if;
 select count(*),coalesce(sum((x->>'debit')::numeric),0),coalesce(sum((x->>'credit')::numeric),0) into v_count,v_debit,v_credit from jsonb_array_elements(p_lines) x;
 if v_count<2 or v_count>30 then raise exception 'A journal must have 2 to 30 lines.'; end if;
 if v_debit<=0 or round(v_debit,2)<>round(v_credit,2) then raise exception 'Journal debits and credits must be equal and greater than zero.'; end if;
 if exists(select 1 from jsonb_array_elements(p_lines) x where coalesce((x->>'debit')::numeric,0)<0 or coalesce((x->>'credit')::numeric,0)<0 or ((coalesce((x->>'debit')::numeric,0)>0)=(coalesce((x->>'credit')::numeric,0)>0))) then raise exception 'Each journal line must have either a debit or a credit, never both.'; end if;
 if exists(select 1 from jsonb_array_elements(p_lines) x where not exists(select 1 from public.finance_accounts a where a.id=(x->>'account_id')::uuid and a.organization_id=v_org_id and a.is_active)) then raise exception 'Every line must use an active account from this workspace.'; end if;
 insert into public.accounting_journal_entries(organization_id,entry_date,source_type,description,status,debit_total,credit_total,created_by,posted_by,posted_at)
 values(v_org_id,coalesce(p_date,current_date),'manual',trim(p_description),'posted',round(v_debit,2),round(v_credit,2),v_user_id,v_user_id,now()) returning id into v_je;
 insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit)
 select v_org_id,v_je,(x->>'account_id')::uuid,left(trim(coalesce(x->>'description','')),250),round(coalesce((x->>'debit')::numeric,0),2),round(coalesce((x->>'credit')::numeric,0),2) from jsonb_array_elements(p_lines) x;
 return v_je;
end; $$;

revoke all on function public.issue_sales_invoice(uuid,date,text) from public,anon;
revoke all on function public.record_sales_payment(uuid,date,numeric,text,text,text) from public,anon;
revoke all on function public.record_finance_expense(date,text,text,numeric,text,text,text,text) from public,anon;
revoke all on function public.record_other_income(date,text,numeric,text,text) from public,anon;
revoke all on function public.create_manual_journal(date,text,jsonb) from public,anon;
grant execute on function public.issue_sales_invoice(uuid,date,text) to authenticated;
grant execute on function public.record_sales_payment(uuid,date,numeric,text,text,text) to authenticated;
grant execute on function public.record_finance_expense(date,text,text,numeric,text,text,text,text) to authenticated;
grant execute on function public.record_other_income(date,text,numeric,text,text) to authenticated;
grant execute on function public.create_manual_journal(date,text,jsonb) to authenticated;
