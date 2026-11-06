-- SupplyOS finance / procurement / recovery / payroll demo data.
-- Run ONLY in a development/demo workspace, after all finance migrations and seed_demo_data.sql.
-- Everything is prefixed DEMO or labelled DEMO DATA; rerunning reuses those records.
do $$
declare
 v_org uuid; v_owner uuid; r record; v_supplier uuid; v_product uuid; v_warehouse uuid;
begin
 select o.id,o.owner_id into v_org,v_owner from public.organizations o order by o.created_at desc limit 1;
 if v_org is null or v_owner is null then raise exception 'Create/sign in to a SupplyOS workspace before seeding demo data.'; end if;
 perform set_config('request.jwt.claim.sub',v_owner::text,true);

 for r in select * from (values
  ('DEMO-SUP-01','Northstar Packaging','Lahore','0300-5550101'),
  ('DEMO-SUP-02','Punjab Raw Materials','Gujranwala','0300-5550102'),
  ('DEMO-SUP-03','Crescent Industrial Supply','Faisalabad','0300-5550103'),
  ('DEMO-SUP-04','Indus Chemicals & Additives','Karachi','0300-5550104'),
  ('DEMO-SUP-05','Prime Labels & Print','Lahore','0300-5550105'),
  ('DEMO-SUP-06','Frontier Transport Services','Peshawar','0300-5550106'),
  ('DEMO-SUP-07','Metro Warehouse Supplies','Rawalpindi','0300-5550107'),
  ('DEMO-SUP-08','Coastal Plastics Traders','Hyderabad','0300-5550108')
 ) as s(code,name,city,phone)
 loop
  if not exists(select 1 from public.suppliers where organization_id=v_org and supplier_code=r.code) then
   perform public.create_stock_supplier(r.code,r.name,r.phone,lower(replace(r.name,' ','') )||'@example.test','Demo supplier address',r.city,30,'DEMO DATA — replace with verified supplier terms before live purchasing.');
  end if;
 end loop;

 for r in select * from (values
  ('DEMO-EMP-001','Amina Shah','Finance','Accounts Officer',68000::numeric,8000::numeric,4500::numeric,2500::numeric,2000::numeric,2.5::numeric),
  ('DEMO-EMP-002','Hamza Rauf','Dispatch','Dispatch Supervisor',82000,9000,6500,3000,2500,3),
  ('DEMO-EMP-003','Zara Malik','Warehouse','Inventory Controller',61000,7000,4500,2000,1500,2),
  ('DEMO-EMP-004','Bilal Ahmed','Production','Line Supervisor',95000,12000,7000,4500,3000,4),
  ('DEMO-EMP-005','Hira Qureshi','Sales','Sales Executive',72000,8000,5000,6000,1500,2.5),
  ('DEMO-EMP-006','Usman Tariq','Fleet','Fleet Coordinator',76000,8500,6500,2500,2000,2.5),
  ('DEMO-EMP-007','Noor Fatima','Human Resources','HR Officer',70000,8000,4500,2000,1500,2.5),
  ('DEMO-EMP-008','Danish Iqbal','Production','Machine Operator',54000,6000,4000,1500,1000,1.5),
  ('DEMO-EMP-009','Maham Ali','Procurement','Procurement Officer',67000,7500,5000,2500,1500,2),
  ('DEMO-EMP-010','Saad Khalid','IT','Systems Support',88000,10000,6000,3500,2500,3.5),
  ('DEMO-EMP-011','Iqra Siddiqui','Customer Service','Customer Support Lead',64000,7000,4500,2500,1200,2),
  ('DEMO-EMP-012','Farhan Aslam','Warehouse','Warehouse Associate',48000,5500,3500,1000,800,1)
 ) as e(empno,fullname,department,designation,basic,housing,transport,other,deduction,tax)
 loop
  if not exists(select 1 from public.employees where organization_id=v_org and employee_no=r.empno) then
   perform public.add_payroll_employee(r.empno,r.fullname,r.department,r.designation,lower(replace(r.fullname,' ','.'))||'@example.test','0300-555'||right(r.empno,4),(current_date-interval '1 year')::date,r.basic,r.housing,r.transport,r.other,r.deduction,r.tax,'full_time');
  end if;
 end loop;

 select id into v_warehouse from public.warehouses where organization_id=v_org and is_active order by is_default desc,created_at limit 1;
 if v_warehouse is null then v_warehouse:=public.create_stock_warehouse('DEMO-WH-01','Demo Central Warehouse','Industrial Estate','Gujranwala','Demo Warehouse Manager','0300-5550199',true); end if;

 -- Ordered POs are intentionally not received; they do not inflate inventory.
 for r in select * from (values
  ('DEMO-SUP-01','DEMO-PO-NOTE-01',1,120::numeric,185::numeric,14),
  ('DEMO-SUP-02','DEMO-PO-NOTE-02',2,80,420,10),
  ('DEMO-SUP-03','DEMO-PO-NOTE-03',3,200,74,7),
  ('DEMO-SUP-04','DEMO-PO-NOTE-04',4,60,960,12),
  ('DEMO-SUP-05','DEMO-PO-NOTE-05',5,500,18,5),
  ('DEMO-SUP-08','DEMO-PO-NOTE-06',6,150,255,16)
 ) as po(supplier_code,ref,product_rank,qty,cost,days)
 loop
  if not exists(select 1 from public.purchase_orders where organization_id=v_org and notes like r.ref||'%') then
   select id into v_supplier from public.suppliers where organization_id=v_org and supplier_code=r.supplier_code;
   select id into v_product from public.products where organization_id=v_org order by sku offset (r.product_rank-1) limit 1;
   if v_supplier is not null and v_product is not null then perform public.create_stock_purchase_order_multi(v_supplier,v_warehouse,jsonb_build_array(jsonb_build_object('product_id',v_product,'quantity',r.qty,'unit_cost',r.cost)),current_date+r.days,r.ref||' — DEMO DATA, not a live supplier commitment'); end if;
  end if;
 end loop;

 for r in select * from (values
  ('DEMO - Monthly factory rent',6200,185000::numeric,'Demo Industrial Estate'),
  ('DEMO - Electricity and utilities',6300,72400,'Demo Utility Provider'),
  ('DEMO - Vehicle fuel and delivery',6100,46800,'Demo Fleet Fuel'),
  ('DEMO - Equipment maintenance',6500,22500,'Demo Engineering Works'),
  ('DEMO - Office supplies',6400,9800,'Demo Office Mart'),
  ('DEMO - Warehouse repairs',6500,15750,'Demo Maintenance Co'),
  ('DEMO - Internet and communications',6400,7200,'Demo Telecom'),
  ('DEMO - Miscellaneous operations',6900,11200,'Demo Operations Vendor')
 ) as ex(description,account_code,amount,vendor)
 loop
  if not exists(select 1 from public.finance_expenses where organization_id=v_org and description=r.description) then
   perform public.record_finance_expense(current_date-1,r.account_code::text,'1010',r.amount,r.description,r.vendor,'bank_transfer','DEMO-SEED-'||replace(r.description,' ','-'));
  end if;
 end loop;

 for r in select * from (values
  ('DEMO - Scrap material recovery',18500::numeric),
  ('DEMO - Supplier rebate received',12500),
  ('DEMO - Pallet deposit returned',8000)
 ) as inc(description,amount)
 loop
  if not exists(select 1 from public.accounting_journal_entries where organization_id=v_org and source_type='other_income' and description=r.description) then
   perform public.record_other_income(current_date-2,'1010',r.amount,r.description,'DEMO-SEED-INCOME');
  end if;
 end loop;

 -- Only demo bookings are invoiced by this seed.
 for r in select b.id,row_number() over(order by b.booking_date desc,b.booking_no desc) as rn from public.bookings b where b.organization_id=v_org and b.status='completed' and b.total_amount>0 and b.booking_no like 'DEMO-BK-%'
  and not exists(select 1 from public.sales_invoices i where i.organization_id=v_org and i.booking_id=b.id)
  order by b.booking_date desc,b.booking_no desc limit 8
 loop
  perform public.issue_sales_invoice(r.id,case when r.rn=1 then current_date-45 when r.rn=2 then current_date-18 when r.rn=3 then current_date-4 else current_date+30 end,'DEMO DATA — sample invoice; confirm customer terms before use.');
 end loop;

 for r in select i.id,i.invoice_no,i.total_amount from public.sales_invoices i where i.organization_id=v_org and i.notes like 'DEMO DATA%' and i.total_amount>100
  and not exists(select 1 from public.sales_payments p where p.organization_id=v_org and p.reference='DEMO-SEED-PAY-'||i.invoice_no)
  order by i.created_at limit 3
 loop
  perform public.record_sales_payment(r.id,current_date-1,round(r.total_amount*0.3,2),'bank_transfer','DEMO-SEED-PAY-'||r.invoice_no,'1010');
 end loop;

 -- Add a small collection-queue scenario for the demo invoices with outstanding balances.
 for r in
  select i.id as invoice_id,i.customer_id,i.invoice_no,i.balance_due,row_number() over(order by i.due_date,i.created_at) as rn
  from public.sales_invoices i
  where i.organization_id=v_org and i.notes like 'DEMO DATA%' and i.balance_due>0
   and not exists(select 1 from public.sales_recovery_tasks t where t.organization_id=v_org and t.invoice_id=i.id and t.summary like 'DEMO - %')
  order by i.due_date,i.created_at limit 4
 loop
  perform public.create_sales_recovery_task(r.customer_id,r.invoice_id,current_date+(r.rn::int-2),
   case when r.rn=1 then 'urgent' when r.rn=2 then 'high' when r.rn=3 then 'medium' else 'low' end,
   case when r.rn=1 then 'payment_promise' when r.rn=2 then 'call' when r.rn=3 then 'email' else 'visit' end,
   case when r.rn=1 then 'DEMO - Confirm promised payment' when r.rn=2 then 'DEMO - Call customer about overdue invoice' when r.rn=3 then 'DEMO - Email statement and balance' else 'DEMO - Schedule account visit' end,
   'DEMO DATA — sample recovery activity. Replace with real contact notes before operational use.');
 end loop;

 -- Leave the payroll run in draft so reviewers must inspect it before approval/payment.
 if not exists(select 1 from public.payroll_runs where organization_id=v_org and period_start=date_trunc('month',current_date)::date and period_end=(date_trunc('month',current_date)+interval '1 month - 1 day')::date) then
  perform public.create_monthly_payroll_run(current_date,'DEMO DATA — review sample salary assumptions and local statutory deductions before approval.');
 end if;
end $$;
