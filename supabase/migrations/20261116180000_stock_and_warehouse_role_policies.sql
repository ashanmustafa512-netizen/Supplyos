-- Stock and warehouse controls belong to Owner and Manager apps.
-- Employees still read shop and product catalogues to submit bookings, but they
-- cannot browse supplier pricing, purchase orders, or stock adjustment history.

drop policy if exists suppliers_read_org on public.suppliers;
create policy suppliers_read_owner_manager on public.suppliers
for select to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = suppliers.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

drop policy if exists warehouses_read_org on public.warehouses;
create policy warehouses_read_owner_manager on public.warehouses
for select to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = warehouses.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

drop policy if exists purchase_orders_read_org on public.purchase_orders;
create policy purchase_orders_read_owner_manager on public.purchase_orders
for select to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = purchase_orders.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

drop policy if exists purchase_order_items_read_org on public.purchase_order_items;
create policy purchase_order_items_read_owner_manager on public.purchase_order_items
for select to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = purchase_order_items.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

drop policy if exists stock_movements_read_org on public.stock_movements;
create policy stock_movements_read_owner_manager on public.stock_movements
for select to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = stock_movements.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

-- Sales and stock apps no longer include employee-level company-wide data access.
-- The cash/bank account lookup stays available to managers for collections only.
drop policy if exists finance_accounts_read_role_limited on public.finance_accounts;
create policy finance_accounts_read_owner_manager on public.finance_accounts
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
);

-- Retain the existing inventory ledger transactions but restrict all mutation
-- entry points to owner/admin/manager roles.
do $stock_hardening$
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
        'save_stock_product',
        'create_stock_supplier',
        'create_stock_warehouse',
        'create_stock_purchase_order_multi',
        'receive_stock_purchase_order_multi',
        'adjust_stock_balance'
      )
  loop
    v_definition := pg_get_functiondef(v_function.oid);
    v_original := v_definition;
    v_definition := replace(
      v_definition,
      'role in (''owner'',''admin'',''manager'',''staff'')',
      'role in (''owner'',''admin'',''manager'')'
    );
    if v_definition = v_original then
      raise exception 'Could not apply owner/manager stock permission hardening to function OID %.', v_function.oid;
    end if;
    execute v_definition;
    v_updated_count := v_updated_count + 1;
  end loop;

  if v_updated_count <> 6 then
    raise exception 'Expected to harden 6 stock/warehouse functions; hardened %.', v_updated_count;
  end if;
end;
$stock_hardening$;
