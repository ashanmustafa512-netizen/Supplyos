-- Employee maintenance, monthly payroll, review, approval and payment workflows.
create or replace function public.add_payroll_employee(
 p_employee_no text,p_full_name text,p_department text,p_designation text,p_email text,p_phone text,
 p_hire_date date,p_monthly_basic numeric,p_housing_allowance numeric,p_transport_allowance numeric,
 p_other_allowance numeric,p_fixed_deduction numeric,p_tax_percent numeric,p_employment_type text default 'full_time'
) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_id uuid;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 if not exists(select 1 from public.memberships where organization_id=v_org_id and user_id=v_user_id and role in ('owner','admin','manager','accountant')) then raise exception 'You do not have payroll administration permission.'; end if;
 if nullif(trim(p_employee_no),'') is null or nullif(trim(p_full_name),'') is null then raise exception 'Employee number and name are required.'; end if;
 if least(coalesce(p_monthly_basic,-1),coalesce(p_housing_allowance,-1),coalesce(p_transport_allowance,-1),coalesce(p_other_allowance,-1),coalesce(p_fixed_deduction,-1))<0 or coalesce(p_tax_percent,-1)<0 or p_tax_percent>100 then raise exception 'Salary components must be non-negative and tax must be between 0 and 100.'; end if;
 if p_employment_type not in ('full_time','part_time','contract','temporary') then raise exception 'Choose a valid employment type.'; end if;
 insert into public.employees(organization_id,employee_no,full_name,department,designation,email,phone,hire_date,monthly_basic,housing_allowance,transport_allowance,other_allowance,fixed_deduction,tax_percent,employment_type)
 values(v_org_id,upper(trim(p_employee_no)),trim(p_full_name),left(trim(coalesce(p_department,'General')),100),left(trim(coalesce(p_designation,'')),120),left(trim(coalesce(p_email,'')),180),left(trim(coalesce(p_phone,'')),40),coalesce(p_hire_date,current_date),p_monthly_basic,p_housing_allowance,p_transport_allowance,p_other_allowance,p_fixed_deduction,p_tax_percent,p_employment_type) returning id into v_id;
 return v_id;
exception when unique_violation then raise exception 'That employee number already exists in this workspace.'; end; $$;

create or replace function public.update_payroll_employee(
 p_employee_id uuid,p_department text,p_designation text,p_monthly_basic numeric,
 p_housing_allowance numeric,p_transport_allowance numeric,p_other_allowance numeric,
 p_fixed_deduction numeric,p_tax_percent numeric,p_status text
) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 if not exists(select 1 from public.memberships where organization_id=v_org_id and user_id=v_user_id and role in ('owner','admin','manager','accountant')) then raise exception 'You do not have payroll administration permission.'; end if;
 if least(coalesce(p_monthly_basic,-1),coalesce(p_housing_allowance,-1),coalesce(p_transport_allowance,-1),coalesce(p_other_allowance,-1),coalesce(p_fixed_deduction,-1))<0 or coalesce(p_tax_percent,-1)<0 or p_tax_percent>100 then raise exception 'Salary components must be non-negative and tax must be between 0 and 100.'; end if;
 if p_status not in ('active','on_leave','inactive') then raise exception 'Choose a valid employee status.'; end if;
 update public.employees set department=left(trim(coalesce(p_department,'General')),100),designation=left(trim(coalesce(p_designation,'')),120),monthly_basic=p_monthly_basic,housing_allowance=p_housing_allowance,transport_allowance=p_transport_allowance,other_allowance=p_other_allowance,fixed_deduction=p_fixed_deduction,tax_percent=p_tax_percent,status=p_status,updated_at=now()
 where id=p_employee_id and organization_id=v_org_id;
 if not found then raise exception 'Employee not found in this workspace.'; end if;
end; $$;

create or replace function public.create_monthly_payroll_run(p_period_start date,p_notes text default '')
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_start date;v_end date;v_run uuid;v_employee record;v_gross numeric;v_tax numeric;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 if not exists(select 1 from public.memberships where organization_id=v_org_id and user_id=v_user_id and role in ('owner','admin','manager','accountant')) then raise exception 'You do not have payroll administration permission.'; end if;
 v_start:=date_trunc('month',coalesce(p_period_start,current_date))::date;v_end:=(date_trunc('month',v_start)+interval '1 month - 1 day')::date;
 if exists(select 1 from public.payroll_runs where organization_id=v_org_id and period_start=v_start and period_end=v_end and status<>'void') then raise exception 'A payroll run already exists for this month.'; end if;
 insert into public.payroll_runs(organization_id,period_start,period_end,status,notes,created_by) values(v_org_id,v_start,v_end,'draft',left(trim(coalesce(p_notes,'')),1000),v_user_id) returning id into v_run;
 for v_employee in select * from public.employees where organization_id=v_org_id and status='active' and hire_date<=v_end order by employee_no loop
  v_gross:=round(v_employee.monthly_basic+v_employee.housing_allowance+v_employee.transport_allowance+v_employee.other_allowance,2);
  v_tax:=round(v_gross*v_employee.tax_percent/100,2);
  insert into public.payroll_items(organization_id,payroll_run_id,employee_id,basic_salary,allowances,deductions,tax_withheld,notes)
  values(v_org_id,v_run,v_employee.id,v_employee.monthly_basic,v_employee.housing_allowance+v_employee.transport_allowance+v_employee.other_allowance,v_employee.fixed_deduction,v_tax,'');
 end loop;
 if not exists(select 1 from public.payroll_items where payroll_run_id=v_run) then raise exception 'There are no active employees to include in this payroll run.'; end if;
 return v_run;
end; $$;

create or replace function public.update_payroll_item(p_item_id uuid,p_overtime_hours numeric,p_overtime_amount numeric,p_bonus numeric,p_deductions numeric,p_tax_withheld numeric,p_notes text default '')
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_item public.payroll_items%rowtype;v_status text;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 if not exists(select 1 from public.memberships where organization_id=v_org_id and user_id=v_user_id and role in ('owner','admin','manager','accountant')) then raise exception 'You do not have payroll administration permission.'; end if;
 select i.* into v_item from public.payroll_items i where i.id=p_item_id and i.organization_id=v_org_id for update;
 if not found then raise exception 'Payroll item not found in this workspace.'; end if;
 select status into v_status from public.payroll_runs where id=v_item.payroll_run_id and organization_id=v_org_id for update;
 if v_status<>'draft' then raise exception 'Only draft payroll lines can be changed.'; end if;
 if least(coalesce(p_overtime_hours,-1),coalesce(p_overtime_amount,-1),coalesce(p_bonus,-1),coalesce(p_deductions,-1),coalesce(p_tax_withheld,-1))<0 then raise exception 'Hours, overtime, bonus, deductions, and tax cannot be negative.'; end if;
 if v_item.basic_salary+v_item.allowances+p_overtime_amount+p_bonus<p_deductions+p_tax_withheld then raise exception 'Net pay cannot be negative.'; end if;
 update public.payroll_items set overtime_hours=p_overtime_hours,overtime_amount=p_overtime_amount,bonus=p_bonus,deductions=p_deductions,tax_withheld=p_tax_withheld,notes=left(trim(coalesce(p_notes,'')),1000) where id=p_item_id;
end; $$;

create or replace function public.payroll_run_action(p_run_id uuid,p_action text,p_payment_account_code text default '1010')
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_run public.payroll_runs%rowtype;v_je uuid;v_wages uuid;v_payable uuid;v_tax uuid;v_ded uuid;v_bank uuid;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 if not exists(select 1 from public.memberships where organization_id=v_org_id and user_id=v_user_id and role in ('owner','admin','manager','accountant')) then raise exception 'You do not have payroll administration permission.'; end if;
 select * into v_run from public.payroll_runs where id=p_run_id and organization_id=v_org_id for update;
 if not found then raise exception 'Payroll run not found in this workspace.'; end if;
 if p_action='approve' then
  if v_run.status<>'draft' then raise exception 'Only draft payroll runs can be approved.'; end if;
  if not exists(select 1 from public.payroll_items where payroll_run_id=v_run.id) then raise exception 'This payroll run has no employees.'; end if;
  select id into v_wages from public.finance_accounts where organization_id=v_org_id and code='6000';
  select id into v_payable from public.finance_accounts where organization_id=v_org_id and code='2200';
  select id into v_tax from public.finance_accounts where organization_id=v_org_id and code='2100';
  select id into v_ded from public.finance_accounts where organization_id=v_org_id and code='2210';
  insert into public.accounting_journal_entries(organization_id,entry_date,source_type,source_id,description,status,debit_total,credit_total,created_by,posted_by,posted_at)
  values(v_org_id,current_date,'payroll_accrual',v_run.id,'Payroll accrual '||v_run.run_no,'posted',v_run.gross_total,v_run.gross_total,v_user_id,v_user_id,now()) returning id into v_je;
  insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit)
  values(v_org_id,v_je,v_wages,'Gross wages',v_run.gross_total,0),(v_org_id,v_je,v_payable,'Net payroll payable',0,v_run.net_total);
  if v_run.tax_total>0 then insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit) values(v_org_id,v_je,v_tax,'Payroll tax withheld',0,v_run.tax_total); end if;
  if v_run.deduction_total>0 then insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit) values(v_org_id,v_je,v_ded,'Employee deductions payable',0,v_run.deduction_total); end if;
  update public.payroll_runs set status='approved',approved_by=v_user_id,approved_at=now(),journal_entry_id=v_je,updated_at=now() where id=v_run.id;
 elsif p_action='pay' then
  if v_run.status<>'approved' then raise exception 'Only approved payroll runs can be paid.'; end if;
  select id into v_bank from public.finance_accounts where organization_id=v_org_id and code=trim(p_payment_account_code) and account_type='asset' and is_active;
  if v_bank is null then raise exception 'Choose a valid cash/bank account.'; end if;
  select id into v_payable from public.finance_accounts where organization_id=v_org_id and code='2200';
  insert into public.accounting_journal_entries(organization_id,entry_date,source_type,source_id,description,status,debit_total,credit_total,created_by,posted_by,posted_at)
  values(v_org_id,current_date,'payroll_payment',v_run.id,'Payroll payment '||v_run.run_no,'posted',v_run.net_total,v_run.net_total,v_user_id,v_user_id,now()) returning id into v_je;
  insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit)
  values(v_org_id,v_je,v_payable,'Settle net payroll payable',v_run.net_total,0),(v_org_id,v_je,v_bank,'Pay net salaries',0,v_run.net_total);
  update public.payroll_runs set status='paid',paid_by=v_user_id,paid_at=now(),payment_date=current_date,payment_journal_entry_id=v_je,updated_at=now() where id=v_run.id;
 elsif p_action='void' then
  if v_run.status<>'draft' then raise exception 'Only draft payroll runs can be voided; posted runs need a reversal journal.'; end if;
  update public.payroll_runs set status='void',updated_at=now() where id=v_run.id;
 else raise exception 'Unsupported payroll action.'; end if;
end; $$;

revoke all on function public.add_payroll_employee(text,text,text,text,text,text,date,numeric,numeric,numeric,numeric,numeric,numeric,text) from public,anon;
revoke all on function public.update_payroll_employee(uuid,text,text,numeric,numeric,numeric,numeric,numeric,numeric,text) from public,anon;
revoke all on function public.create_monthly_payroll_run(date,text) from public,anon;
revoke all on function public.update_payroll_item(uuid,numeric,numeric,numeric,numeric,numeric,text) from public,anon;
revoke all on function public.payroll_run_action(uuid,text,text) from public,anon;
grant execute on function public.add_payroll_employee(text,text,text,text,text,text,date,numeric,numeric,numeric,numeric,numeric,numeric,text) to authenticated;
grant execute on function public.update_payroll_employee(uuid,text,text,numeric,numeric,numeric,numeric,numeric,numeric,text) to authenticated;
grant execute on function public.create_monthly_payroll_run(date,text) to authenticated;
grant execute on function public.update_payroll_item(uuid,numeric,numeric,numeric,numeric,numeric,text) to authenticated;
grant execute on function public.payroll_run_action(uuid,text,text) to authenticated;
