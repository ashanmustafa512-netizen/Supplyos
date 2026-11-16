-- Operational read/write permissions for the three-app role model.
-- Shops and products remain readable for booking creation, but only owner/manager
-- users can create or edit master records.

drop policy if exists booking_events_read_org on public.booking_events;
create policy booking_events_read_by_role on public.booking_events
for select to authenticated
using (
  exists (
    select 1 from public.bookings b
    join public.memberships m on m.organization_id = b.organization_id
    where b.id = booking_events.booking_id
      and m.user_id = (select auth.uid())
      and (
        m.role in ('owner', 'admin', 'manager')
        or (m.role = 'staff' and b.created_by = (select auth.uid()))
      )
  )
);

drop policy if exists customers_insert_org on public.customers;
create policy customers_insert_owner_manager on public.customers
for insert to authenticated
with check (
  exists (
    select 1 from public.memberships m
    where m.organization_id = customers.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

drop policy if exists customers_update_org on public.customers;
create policy customers_update_owner_manager on public.customers
for update to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = customers.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
)
with check (
  exists (
    select 1 from public.memberships m
    where m.organization_id = customers.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

drop policy if exists products_insert_org on public.products;
create policy products_insert_owner_manager on public.products
for insert to authenticated
with check (
  exists (
    select 1 from public.memberships m
    where m.organization_id = products.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

drop policy if exists products_update_org on public.products;
create policy products_update_owner_manager on public.products
for update to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = products.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
)
with check (
  exists (
    select 1 from public.memberships m
    where m.organization_id = products.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

drop policy if exists sales_invoices_read_org on public.sales_invoices;
create policy sales_invoices_read_owner_manager on public.sales_invoices
for select to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = sales_invoices.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

drop policy if exists sales_allocations_read_org on public.sales_payment_allocations;
create policy sales_allocations_read_owner_manager on public.sales_payment_allocations
for select to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = sales_payment_allocations.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

drop policy if exists sales_payments_read_org on public.sales_payments;
create policy sales_payments_read_owner_manager on public.sales_payments
for select to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = sales_payments.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

drop policy if exists sales_recovery_tasks_read_org on public.sales_recovery_tasks;
create policy sales_recovery_tasks_read_owner_manager on public.sales_recovery_tasks
for select to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = sales_recovery_tasks.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

-- Keep the existing transactional billing / receipt / recovery logic, and only
-- narrow the membership gate. Employees and standalone accountant roles are not
-- given the manager's company-wide sales and recovery powers.
do $sales_hardening$
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
        'issue_sales_invoice',
        'record_sales_payment',
        'create_sales_recovery_task',
        'update_sales_recovery_task'
      )
  loop
    v_definition := pg_get_functiondef(v_function.oid);
    v_original := v_definition;
    v_definition := replace(
      v_definition,
      'role in (''owner'',''admin'',''manager'',''accountant'',''staff'')',
      'role in (''owner'',''admin'',''manager'')'
    );
    if v_definition = v_original then
      raise exception 'Could not apply manager-only sales permission hardening to function OID %.', v_function.oid;
    end if;
    execute v_definition;
    v_updated_count := v_updated_count + 1;
  end loop;

  if v_updated_count <> 4 then
    raise exception 'Expected to harden 4 sales/recovery functions; hardened %.', v_updated_count;
  end if;
end;
$sales_hardening$;
