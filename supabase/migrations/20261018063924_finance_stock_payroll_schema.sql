-- SupplyOS finance, stock, sales, procurement, and payroll schema.
-- Additive migration after the SupplyOS base + dispatch migrations.
alter table public.products
  add column if not exists category text not null default 'General',
  add column if not exists barcode text not null default '',
  add column if not exists raw_material_cost numeric(14,2) not null default 0 check (raw_material_cost >= 0),
  add column if not exists direct_labor_cost numeric(14,2) not null default 0 check (direct_labor_cost >= 0),
  add column if not exists production_overhead numeric(14,2) not null default 0 check (production_overhead >= 0),
  add column if not exists production_cost numeric(14,2) not null default 0 check (production_cost >= 0),
  add column if not exists reorder_level numeric(14,3) not null default 0 check (reorder_level >= 0),
  add column if not exists default_supplier_id uuid;
update public.products set raw_material_cost=unit_cost, production_cost=unit_cost where production_cost=0 and unit_cost>0;

create table if not exists public.finance_accounts (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 code text not null, name text not null,
 account_type text not null check (account_type in ('asset','liability','equity','revenue','expense')),
 description text not null default '', is_control boolean not null default false,
 is_system boolean not null default false, is_active boolean not null default true,
 created_at timestamptz not null default now(), unique (organization_id,code)
);
create table if not exists public.accounting_journal_entries (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 entry_no text not null default ('JE-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
 entry_date date not null default current_date, source_type text not null default 'manual', source_id uuid,
 description text not null, status text not null default 'draft' check (status in ('draft','posted','void')),
 debit_total numeric(14,2) not null default 0 check (debit_total>=0), credit_total numeric(14,2) not null default 0 check (credit_total>=0),
 created_by uuid not null references auth.users(id), posted_by uuid references auth.users(id), posted_at timestamptz,
 created_at timestamptz not null default now(), unique (organization_id,entry_no)
);
create table if not exists public.accounting_journal_lines (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 journal_entry_id uuid not null references public.accounting_journal_entries(id) on delete cascade,
 account_id uuid not null references public.finance_accounts(id) on delete restrict,
 description text not null default '', debit numeric(14,2) not null default 0 check (debit>=0), credit numeric(14,2) not null default 0 check (credit>=0),
 created_at timestamptz not null default now(), check (not (debit>0 and credit>0)), check (debit>0 or credit>0)
);
create table if not exists public.finance_expenses (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 expense_no text not null default ('EX-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))), expense_date date not null default current_date,
 expense_account_id uuid not null references public.finance_accounts(id), paid_from_account_id uuid not null references public.finance_accounts(id),
 vendor text not null default '', description text not null, amount numeric(14,2) not null check (amount>0),
 payment_method text not null default 'bank_transfer' check (payment_method in ('cash','bank_transfer','cheque','card','other')),
 reference text not null default '', journal_entry_id uuid references public.accounting_journal_entries(id),
 created_by uuid not null references auth.users(id), created_at timestamptz not null default now(), unique (organization_id,expense_no)
);
create table if not exists public.suppliers (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 supplier_code text not null, name text not null, phone text not null default '', email text not null default '',
 address text not null default '', city text not null default '', payment_terms_days integer not null default 30 check (payment_terms_days between 0 and 365),
 notes text not null default '', is_active boolean not null default true, created_at timestamptz not null default now(), unique (organization_id,supplier_code)
);
create table if not exists public.warehouses (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 code text not null, name text not null, address text not null default '', city text not null default '',
 contact_name text not null default '', contact_phone text not null default '', is_default boolean not null default false,
 is_active boolean not null default true, created_at timestamptz not null default now(), unique (organization_id,code)
);
create unique index if not exists warehouses_one_default_per_org on public.warehouses(organization_id) where is_default=true;
alter table public.products drop constraint if exists products_default_supplier_id_fkey;
alter table public.products add constraint products_default_supplier_id_fkey foreign key (default_supplier_id) references public.suppliers(id) on delete set null;

create table if not exists public.stock_movements (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 product_id uuid not null references public.products(id) on delete restrict, warehouse_id uuid references public.warehouses(id) on delete set null,
 movement_type text not null check (movement_type in ('opening_balance','receipt','reservation','release','dispatch','adjustment_in','adjustment_out','transfer_in','transfer_out','production','revaluation')),
 quantity_delta numeric(14,3) not null default 0, reserved_delta numeric(14,3) not null default 0,
 stock_after numeric(14,3) not null default 0, reserved_after numeric(14,3) not null default 0,
 unit_cost numeric(14,2) not null default 0, reference_type text not null default '', reference_code text not null default '',
 notes text not null default '', created_by uuid references auth.users(id), created_at timestamptz not null default now(),
 check (quantity_delta<>0 or reserved_delta<>0 or movement_type='revaluation')
);
create table if not exists public.purchase_orders (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 po_no text not null default ('PO-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
 supplier_id uuid not null references public.suppliers(id) on delete restrict, warehouse_id uuid not null references public.warehouses(id) on delete restrict,
 order_date date not null default current_date, expected_date date,
 status text not null default 'ordered' check (status in ('draft','ordered','partially_received','received','cancelled')),
 subtotal numeric(14,2) not null default 0 check (subtotal>=0), received_value numeric(14,2) not null default 0 check (received_value>=0),
 notes text not null default '', created_by uuid not null references auth.users(id), received_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (organization_id,po_no)
);
create table if not exists public.purchase_order_items (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
 product_id uuid not null references public.products(id) on delete restrict,
 quantity_ordered numeric(14,3) not null check (quantity_ordered>0), quantity_received numeric(14,3) not null default 0 check (quantity_received>=0 and quantity_received<=quantity_ordered),
 unit_cost numeric(14,2) not null check (unit_cost>=0), line_total numeric(14,2) generated always as (round(quantity_ordered*unit_cost,2)) stored, created_at timestamptz not null default now()
);

create table if not exists public.sales_invoices (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 invoice_no text not null default ('INV-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
 booking_id uuid not null references public.bookings(id) on delete restrict, customer_id uuid not null references public.customers(id) on delete restrict,
 issue_date date not null default current_date, due_date date not null, subtotal numeric(14,2) not null default 0 check (subtotal>=0),
 tax_amount numeric(14,2) not null default 0 check (tax_amount>=0), total_amount numeric(14,2) not null check (total_amount>=0),
 amount_paid numeric(14,2) not null default 0 check (amount_paid>=0 and amount_paid<=total_amount),
 balance_due numeric(14,2) generated always as (round(total_amount-amount_paid,2)) stored,
 status text not null default 'open' check (status in ('open','partial','paid','void')), notes text not null default '',
 journal_entry_id uuid references public.accounting_journal_entries(id), created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(), unique (organization_id,invoice_no), unique (booking_id)
);
create table if not exists public.sales_payments (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 receipt_no text not null default ('RC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
 invoice_id uuid not null references public.sales_invoices(id) on delete restrict, customer_id uuid not null references public.customers(id) on delete restrict,
 payment_date date not null default current_date, amount numeric(14,2) not null check (amount>0),
 payment_method text not null default 'bank_transfer' check (payment_method in ('cash','bank_transfer','cheque','card','other')),
 reference text not null default '', received_into_account_id uuid not null references public.finance_accounts(id),
 journal_entry_id uuid references public.accounting_journal_entries(id), created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(), unique (organization_id,receipt_no)
);
create table if not exists public.sales_payment_allocations (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 payment_id uuid not null references public.sales_payments(id) on delete cascade, invoice_id uuid not null references public.sales_invoices(id) on delete restrict,
 amount numeric(14,2) not null check (amount>0), created_at timestamptz not null default now()
);

create table if not exists public.employees (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 employee_no text not null, full_name text not null, email text not null default '', phone text not null default '',
 department text not null default 'General', designation text not null default '',
 employment_type text not null default 'full_time' check (employment_type in ('full_time','part_time','contract','temporary')),
 hire_date date not null default current_date, monthly_basic numeric(14,2) not null default 0 check (monthly_basic>=0),
 housing_allowance numeric(14,2) not null default 0 check (housing_allowance>=0), transport_allowance numeric(14,2) not null default 0 check (transport_allowance>=0),
 other_allowance numeric(14,2) not null default 0 check (other_allowance>=0), fixed_deduction numeric(14,2) not null default 0 check (fixed_deduction>=0),
 tax_percent numeric(5,2) not null default 0 check (tax_percent between 0 and 100),
 status text not null default 'active' check (status in ('active','on_leave','inactive')), notes text not null default '',
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (organization_id,employee_no)
);
create table if not exists public.payroll_runs (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 run_no text not null default ('PR-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
 period_start date not null, period_end date not null, payment_date date,
 status text not null default 'draft' check (status in ('draft','approved','paid','void')),
 gross_total numeric(14,2) not null default 0 check (gross_total>=0), deduction_total numeric(14,2) not null default 0 check (deduction_total>=0),
 tax_total numeric(14,2) not null default 0 check (tax_total>=0), net_total numeric(14,2) not null default 0 check (net_total>=0),
 notes text not null default '', created_by uuid not null references auth.users(id), approved_by uuid references auth.users(id), paid_by uuid references auth.users(id),
 journal_entry_id uuid references public.accounting_journal_entries(id), payment_journal_entry_id uuid references public.accounting_journal_entries(id),
 approved_at timestamptz, paid_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check (period_end>=period_start), unique (organization_id,run_no), unique (organization_id,period_start,period_end)
);
create table if not exists public.payroll_items (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 payroll_run_id uuid not null references public.payroll_runs(id) on delete cascade, employee_id uuid not null references public.employees(id) on delete restrict,
 basic_salary numeric(14,2) not null check (basic_salary>=0), allowances numeric(14,2) not null default 0 check (allowances>=0),
 overtime_hours numeric(10,2) not null default 0 check (overtime_hours>=0), overtime_amount numeric(14,2) not null default 0 check (overtime_amount>=0),
 bonus numeric(14,2) not null default 0 check (bonus>=0), deductions numeric(14,2) not null default 0 check (deductions>=0), tax_withheld numeric(14,2) not null default 0 check (tax_withheld>=0),
 gross_pay numeric(14,2) generated always as (round(basic_salary+allowances+overtime_amount+bonus,2)) stored,
 net_pay numeric(14,2) generated always as (round(basic_salary+allowances+overtime_amount+bonus-deductions-tax_withheld,2)) stored,
 notes text not null default '', created_at timestamptz not null default now(), unique (payroll_run_id,employee_id),
 check (basic_salary+allowances+overtime_amount+bonus>=deductions+tax_withheld)
);

create index if not exists journal_entries_org_date_idx on public.accounting_journal_entries(organization_id,status,entry_date desc);
create index if not exists journal_lines_entry_idx on public.accounting_journal_lines(journal_entry_id);
create index if not exists finance_expenses_org_date_idx on public.finance_expenses(organization_id,expense_date desc);
create index if not exists stock_movements_org_created_idx on public.stock_movements(organization_id,created_at desc);
create index if not exists stock_movements_product_idx on public.stock_movements(product_id,created_at desc);
create index if not exists purchase_orders_org_status_idx on public.purchase_orders(organization_id,status,order_date desc);
create index if not exists sales_invoices_org_due_idx on public.sales_invoices(organization_id,status,due_date);
create index if not exists sales_payments_org_date_idx on public.sales_payments(organization_id,payment_date desc);
create index if not exists employees_org_status_idx on public.employees(organization_id,status,full_name);
create index if not exists payroll_runs_org_period_idx on public.payroll_runs(organization_id,period_start desc);

create or replace function public.supplyos_ensure_finance_defaults(p_org_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 insert into public.finance_accounts(organization_id,code,name,account_type,description,is_control,is_system) values
 (p_org_id,'1000','Cash on hand','asset','Cash float and petty cash',false,true),(p_org_id,'1010','Bank account','asset','Operating bank balances',false,true),
 (p_org_id,'1100','Accounts receivable','asset','Customer invoices outstanding',true,true),(p_org_id,'1200','Inventory asset','asset','Inventory measured at standard/weighted cost',true,true),
 (p_org_id,'1500','Equipment and fixed assets','asset','Equipment and durable factory assets',false,true),(p_org_id,'2000','Accounts payable','liability','Supplier balances from received purchase orders',true,true),
 (p_org_id,'2100','Tax payable','liability','Payroll tax withheld pending remittance',true,true),(p_org_id,'2200','Payroll payable','liability','Net payroll approved but not yet paid',true,true),
 (p_org_id,'2210','Other payroll deductions payable','liability','Employee deductions pending remittance',true,true),(p_org_id,'3000','Owner capital and opening equity','equity','Opening inventory and owner capital',false,true),
 (p_org_id,'3100','Retained earnings','equity','Accumulated profit and loss',false,true),(p_org_id,'4000','Sales revenue','revenue','Revenue from issued customer invoices',true,true),
 (p_org_id,'4100','Other income','revenue','Other operating and non-operating income',false,true),(p_org_id,'4200','Inventory adjustment gain','revenue','Gain from positive inventory adjustments/revaluation',false,true),
 (p_org_id,'5000','Cost of goods sold','expense','Cost of delivered products',true,true),(p_org_id,'6000','Salaries and wages','expense','Gross salary and payroll expense',true,true),
 (p_org_id,'6100','Delivery and freight','expense','Delivery and freight costs',false,true),(p_org_id,'6200','Rent expense','expense','Factory, warehouse, and office rent',false,true),
 (p_org_id,'6300','Utilities expense','expense','Electricity, water, gas, and internet',false,true),(p_org_id,'6400','Office and administration','expense','Office and administration costs',false,true),
 (p_org_id,'6500','Repairs and maintenance','expense','Maintenance and repair costs',false,true),(p_org_id,'6600','Inventory write-off expense','expense','Damaged, lost, or negative inventory adjustments',false,true),
 (p_org_id,'6700','Other payroll deductions expense','expense','Other payroll corrections or employer contributions',false,true),(p_org_id,'6900','Miscellaneous expense','expense','Other categorized expenses',false,true)
 on conflict(organization_id,code) do nothing;
 insert into public.warehouses(organization_id,code,name,is_default,is_active) values(p_org_id,'MAIN','Main Warehouse',true,true) on conflict(organization_id,code) do nothing;
end; $$;
create or replace function public.supplyos_seed_finance_defaults_trigger()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin perform public.supplyos_ensure_finance_defaults(new.id); return new; end; $$;
drop trigger if exists organizations_seed_finance_defaults on public.organizations;
create trigger organizations_seed_finance_defaults after insert on public.organizations for each row execute function public.supplyos_seed_finance_defaults_trigger();

create or replace function public.supplyos_product_stock_audit()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_wh uuid; v_qty numeric:=0; v_reserved numeric:=0; v_type text;
begin
 if tg_op='INSERT' then v_qty:=new.stock_on_hand; v_reserved:=new.stock_reserved; if v_qty=0 and v_reserved=0 then return new; end if; v_type:='opening_balance';
 else v_qty:=new.stock_on_hand-old.stock_on_hand; v_reserved:=new.stock_reserved-old.stock_reserved; if v_qty=0 and v_reserved=0 then return new; end if;
  v_type:=case when v_qty<0 and v_reserved<0 then 'dispatch' when v_qty>0 and v_reserved=0 then 'receipt' when v_qty=0 and v_reserved>0 then 'reservation' when v_qty=0 and v_reserved<0 then 'release' when v_qty>0 then 'adjustment_in' else 'adjustment_out' end;
 end if;
 begin v_wh:=nullif(current_setting('supplyos.warehouse_id',true),'')::uuid; exception when others then v_wh:=null; end;
 if v_wh is null or not exists(select 1 from public.warehouses w where w.id=v_wh and w.organization_id=new.organization_id) then select w.id into v_wh from public.warehouses w where w.organization_id=new.organization_id and w.is_default=true limit 1; end if;
 insert into public.stock_movements(organization_id,product_id,warehouse_id,movement_type,quantity_delta,reserved_delta,stock_after,reserved_after,unit_cost,reference_type,reference_code,notes,created_by)
 values(new.organization_id,new.id,v_wh,v_type,v_qty,v_reserved,new.stock_on_hand,new.stock_reserved,new.unit_cost,'product_balance','','Automatically recorded product stock change',auth.uid());
 perform set_config('supplyos.warehouse_id','',true); return new;
end; $$;
drop trigger if exists product_stock_audit on public.products;
create trigger product_stock_audit after insert or update of stock_on_hand,stock_reserved on public.products for each row execute function public.supplyos_product_stock_audit();

create or replace function public.supplyos_recalc_payroll_totals()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_run uuid;
begin v_run:=case when tg_op='DELETE' then old.payroll_run_id else new.payroll_run_id end;
 update public.payroll_runs r set gross_total=coalesce((select sum(i.gross_pay) from public.payroll_items i where i.payroll_run_id=v_run),0),
  deduction_total=coalesce((select sum(i.deductions) from public.payroll_items i where i.payroll_run_id=v_run),0),
  tax_total=coalesce((select sum(i.tax_withheld) from public.payroll_items i where i.payroll_run_id=v_run),0),
  net_total=coalesce((select sum(i.net_pay) from public.payroll_items i where i.payroll_run_id=v_run),0),updated_at=now() where r.id=v_run;
 return null; end; $$;
drop trigger if exists payroll_items_recalc_run on public.payroll_items;
create trigger payroll_items_recalc_run after insert or update or delete on public.payroll_items for each row execute function public.supplyos_recalc_payroll_totals();

-- Workspace-scoped read access; all financial and stock mutations go through authenticated RPCs.
alter table public.finance_accounts enable row level security;
alter table public.accounting_journal_entries enable row level security;
alter table public.accounting_journal_lines enable row level security;
alter table public.finance_expenses enable row level security;
alter table public.suppliers enable row level security;
alter table public.warehouses enable row level security;
alter table public.stock_movements enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_items enable row level security;
alter table public.sales_invoices enable row level security;
alter table public.sales_payments enable row level security;
alter table public.sales_payment_allocations enable row level security;
alter table public.employees enable row level security;
alter table public.payroll_runs enable row level security;
alter table public.payroll_items enable row level security;
revoke all on public.finance_accounts,public.accounting_journal_entries,public.accounting_journal_lines,public.finance_expenses,public.suppliers,public.warehouses,public.stock_movements,public.purchase_orders,public.purchase_order_items,public.sales_invoices,public.sales_payments,public.sales_payment_allocations,public.employees,public.payroll_runs,public.payroll_items from anon,authenticated;
grant select on public.finance_accounts,public.accounting_journal_entries,public.accounting_journal_lines,public.finance_expenses,public.suppliers,public.warehouses,public.stock_movements,public.purchase_orders,public.purchase_order_items,public.sales_invoices,public.sales_payments,public.sales_payment_allocations,public.employees,public.payroll_runs,public.payroll_items to authenticated;

-- Drop/recreate policies to keep this migration repeatable in a development database.
drop policy if exists finance_accounts_read_org on public.finance_accounts;
create policy finance_accounts_read_org on public.finance_accounts for select to authenticated using (organization_id in(select m.organization_id from public.memberships m where m.user_id=(select auth.uid()) and m.role in('owner','admin','manager','accountant')));
drop policy if exists accounting_journals_read_org on public.accounting_journal_entries;
create policy accounting_journals_read_org on public.accounting_journal_entries for select to authenticated using (organization_id in(select m.organization_id from public.memberships m where m.user_id=(select auth.uid()) and m.role in('owner','admin','manager','accountant')));
drop policy if exists accounting_lines_read_org on public.accounting_journal_lines;
create policy accounting_lines_read_org on public.accounting_journal_lines for select to authenticated using (organization_id in(select m.organization_id from public.memberships m where m.user_id=(select auth.uid()) and m.role in('owner','admin','manager','accountant')));
drop policy if exists finance_expenses_read_org on public.finance_expenses;
create policy finance_expenses_read_org on public.finance_expenses for select to authenticated using (organization_id in(select m.organization_id from public.memberships m where m.user_id=(select auth.uid()) and m.role in('owner','admin','manager','accountant')));
drop policy if exists suppliers_read_org on public.suppliers;
create policy suppliers_read_org on public.suppliers for select to authenticated using (organization_id in(select m.organization_id from public.memberships m where m.user_id=(select auth.uid())));
drop policy if exists warehouses_read_org on public.warehouses;
create policy warehouses_read_org on public.warehouses for select to authenticated using (organization_id in(select m.organization_id from public.memberships m where m.user_id=(select auth.uid())));
drop policy if exists stock_movements_read_org on public.stock_movements;
create policy stock_movements_read_org on public.stock_movements for select to authenticated using (organization_id in(select m.organization_id from public.memberships m where m.user_id=(select auth.uid())));
drop policy if exists purchase_orders_read_org on public.purchase_orders;
create policy purchase_orders_read_org on public.purchase_orders for select to authenticated using (organization_id in(select m.organization_id from public.memberships m where m.user_id=(select auth.uid())));
drop policy if exists purchase_order_items_read_org on public.purchase_order_items;
create policy purchase_order_items_read_org on public.purchase_order_items for select to authenticated using (organization_id in(select m.organization_id from public.memberships m where m.user_id=(select auth.uid())));
drop policy if exists sales_invoices_read_org on public.sales_invoices;
create policy sales_invoices_read_org on public.sales_invoices for select to authenticated using (organization_id in(select m.organization_id from public.memberships m where m.user_id=(select auth.uid()) and m.role in('owner','admin','manager','accountant','staff')));
drop policy if exists sales_payments_read_org on public.sales_payments;
create policy sales_payments_read_org on public.sales_payments for select to authenticated using (organization_id in(select m.organization_id from public.memberships m where m.user_id=(select auth.uid()) and m.role in('owner','admin','manager','accountant','staff')));
drop policy if exists sales_allocations_read_org on public.sales_payment_allocations;
create policy sales_allocations_read_org on public.sales_payment_allocations for select to authenticated using (organization_id in(select m.organization_id from public.memberships m where m.user_id=(select auth.uid()) and m.role in('owner','admin','manager','accountant','staff')));
drop policy if exists employees_read_org on public.employees;
create policy employees_read_org on public.employees for select to authenticated using (organization_id in(select m.organization_id from public.memberships m where m.user_id=(select auth.uid()) and m.role in('owner','admin','manager','accountant')));
drop policy if exists payroll_runs_read_org on public.payroll_runs;
create policy payroll_runs_read_org on public.payroll_runs for select to authenticated using (organization_id in(select m.organization_id from public.memberships m where m.user_id=(select auth.uid()) and m.role in('owner','admin','manager','accountant')));
drop policy if exists payroll_items_read_org on public.payroll_items;
create policy payroll_items_read_org on public.payroll_items for select to authenticated using (organization_id in(select m.organization_id from public.memberships m where m.user_id=(select auth.uid()) and m.role in('owner','admin','manager','accountant')));

revoke all on function public.supplyos_ensure_finance_defaults(uuid) from public,anon,authenticated;
revoke all on function public.supplyos_product_stock_audit() from public,anon,authenticated;
revoke all on function public.supplyos_recalc_payroll_totals() from public,anon,authenticated;
revoke all on function public.supplyos_seed_finance_defaults_trigger() from public,anon,authenticated;
select public.supplyos_ensure_finance_defaults(id) from public.organizations;
