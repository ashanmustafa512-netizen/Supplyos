-- SupplyOS role-based app foundation.
-- Additive migration: keeps historical dispatch/truck records and existing business data.
-- Roles:
--   owner/admin: company-wide oversight and approvals
--   manager: operational bookings, stock/warehouse and sales/recovery
--   staff: create and read only their own bookings
--   accountant: accounting and sales/recovery back-office access

-- The current application uses one active workspace per login. Fail closed rather
-- than silently selecting an arbitrary organization if a login is later multi-tenant.
create or replace function public.supplyos_current_organization_id()
returns uuid
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $function$
declare
  v_count integer;
  v_org_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Please sign in first.';
  end if;

  select count(*), (array_agg(m.organization_id order by m.created_at))[1]
    into v_count, v_org_id
  from public.memberships m
  where m.user_id = auth.uid();

  if v_count = 0 then
    raise exception 'Your account is not linked to a factory workspace.';
  elsif v_count > 1 then
    raise exception 'This account belongs to more than one factory. Select a workspace before continuing.';
  end if;

  return v_org_id;
end;
$function$;

revoke all on function public.supplyos_current_organization_id() from public, anon;
grant execute on function public.supplyos_current_organization_id() to authenticated;

-- Booking creation is available to owner, manager and field staff. Prices/costs
-- remain server-read and the booking + item + event are written transactionally.
create or replace function public.create_booking(
  p_customer_id uuid,
  p_product_id uuid,
  p_quantity numeric,
  p_notes text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_org_id uuid;
  v_role text;
  v_customer public.customers%rowtype;
  v_product public.products%rowtype;
  v_booking_id uuid;
begin
  if v_user_id is null then raise exception 'Please sign in first.'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be greater than zero.'; end if;

  v_org_id := public.supplyos_current_organization_id();
  select m.role into v_role
  from public.memberships m
  where m.organization_id = v_org_id and m.user_id = v_user_id;

  if v_role not in ('owner', 'admin', 'manager', 'staff') then
    raise exception 'Your role is not allowed to create bookings.';
  end if;

  select * into v_customer
  from public.customers
  where id = p_customer_id and organization_id = v_org_id and status = 'active'
  for update;
  if not found then raise exception 'Choose an active shop from your factory.'; end if;

  select * into v_product
  from public.products
  where id = p_product_id and organization_id = v_org_id and is_active = true;
  if not found then raise exception 'Choose an active product from your factory.'; end if;

  insert into public.bookings (organization_id, customer_id, city, region, score_snapshot, notes, created_by)
  values (v_org_id, v_customer.id, v_customer.city, v_customer.region, v_customer.score, left(coalesce(p_notes, ''), 2000), v_user_id)
  returning id into v_booking_id;

  insert into public.booking_items (booking_id, product_id, quantity, unit_price, unit_cost)
  values (v_booking_id, v_product.id, p_quantity, v_product.unit_price, v_product.unit_cost);

  insert into public.booking_events (organization_id, booking_id, actor_id, action, details)
  values (v_org_id, v_booking_id, v_user_id, 'created',
          jsonb_build_object('quantity', p_quantity, 'product_id', p_product_id));

  return v_booking_id;
end;
$function$;

-- Only owner/admin can approve or reject. Managers can complete/cancel approved
-- work; employees can cancel only their own pending booking.
create or replace function public.booking_action(p_booking_id uuid, p_action text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_booking public.bookings%rowtype;
  v_customer public.customers%rowtype;
  v_item record;
  v_available numeric(14,3);
  v_org_id uuid;
  v_next_status public.booking_status;
begin
  if v_user_id is null then raise exception 'Please sign in first.'; end if;
  if p_action not in ('approve', 'reject', 'cancel', 'complete') then
    raise exception 'Unsupported booking action.';
  end if;

  select b.* into v_booking
  from public.bookings b
  where b.id = p_booking_id
  for update;
  if not found then raise exception 'Booking was not found.'; end if;

  v_org_id := v_booking.organization_id;
  select m.role into v_role
  from public.memberships m
  where m.organization_id = v_org_id and m.user_id = v_user_id;
  if v_role is null then raise exception 'You do not have access to this factory booking.'; end if;

  if p_action in ('approve', 'reject') and v_role not in ('owner', 'admin') then
    raise exception 'Only the owner or delegated admin can approve or reject bookings.';
  end if;

  if p_action = 'complete' and v_role not in ('owner', 'admin', 'manager') then
    raise exception 'Only the owner or manager can complete a booking.';
  end if;

  if p_action = 'cancel' then
    if v_role = 'staff' then
      if v_booking.created_by <> v_user_id or v_booking.status <> 'pending_approval' then
        raise exception 'Employees can cancel only their own pending bookings.';
      end if;
    elsif v_role not in ('owner', 'admin', 'manager') then
      raise exception 'Your role is not allowed to cancel this booking.';
    end if;
  end if;

  if p_action = 'approve' then
    if v_booking.status <> 'pending_approval' then raise exception 'Only pending bookings can be approved.'; end if;

    select * into v_customer
    from public.customers
    where id = v_booking.customer_id and organization_id = v_org_id
    for update;
    if not found then raise exception 'Shop record was not found.'; end if;
    if v_customer.credit_used + v_booking.total_amount > v_customer.credit_limit then
      raise exception 'Credit limit exceeded. Review the shop limit or outstanding balance before approving.';
    end if;

    for v_item in
      select i.product_id, i.quantity
      from public.booking_items i
      where i.booking_id = v_booking.id
      order by i.product_id
    loop
      select (p.stock_on_hand - p.stock_reserved) into v_available
      from public.products p
      where p.id = v_item.product_id and p.organization_id = v_org_id
      for update;
      if not found then raise exception 'A product in this booking is no longer available.'; end if;
      if v_available < v_item.quantity then raise exception 'Insufficient available stock for one or more items.'; end if;
    end loop;

    for v_item in
      select i.product_id, i.quantity
      from public.booking_items i
      where i.booking_id = v_booking.id
    loop
      update public.products
      set stock_reserved = stock_reserved + v_item.quantity
      where id = v_item.product_id and organization_id = v_org_id;
    end loop;

    update public.customers
    set credit_used = credit_used + v_booking.total_amount
    where id = v_customer.id;

    v_next_status := 'approved';
    update public.bookings
    set status = v_next_status, approved_by = v_user_id, approved_at = now(), updated_at = now()
    where id = v_booking.id;

  elsif p_action = 'reject' then
    if v_booking.status <> 'pending_approval' then raise exception 'Only pending bookings can be rejected.'; end if;
    v_next_status := 'rejected';
    update public.bookings set status = v_next_status, updated_at = now() where id = v_booking.id;

  elsif p_action = 'cancel' then
    if v_booking.status in ('completed', 'cancelled', 'rejected') then
      raise exception 'This booking can no longer be cancelled.';
    end if;

    if v_booking.status = 'approved' then
      for v_item in
        select i.product_id, i.quantity
        from public.booking_items i
        where i.booking_id = v_booking.id
      loop
        update public.products
        set stock_reserved = greatest(0, stock_reserved - v_item.quantity)
        where id = v_item.product_id and organization_id = v_org_id;
      end loop;

      update public.customers
      set credit_used = greatest(0, credit_used - v_booking.total_amount)
      where id = v_booking.customer_id and organization_id = v_org_id;
    end if;

    v_next_status := 'cancelled';
    update public.bookings set status = v_next_status, updated_at = now() where id = v_booking.id;

  elsif p_action = 'complete' then
    if v_booking.status <> 'approved' then raise exception 'Only approved bookings can be completed.'; end if;

    for v_item in
      select i.product_id, i.quantity
      from public.booking_items i
      where i.booking_id = v_booking.id
    loop
      update public.products
      set stock_on_hand = stock_on_hand - v_item.quantity,
          stock_reserved = stock_reserved - v_item.quantity
      where id = v_item.product_id
        and organization_id = v_org_id
        and stock_reserved >= v_item.quantity
        and stock_on_hand >= v_item.quantity;
      if not found then raise exception 'Stock changed unexpectedly. Refresh inventory and try again.'; end if;
    end loop;

    v_next_status := 'completed';
    update public.bookings set status = v_next_status, updated_at = now() where id = v_booking.id;
  end if;

  insert into public.booking_events (organization_id, booking_id, actor_id, action, details)
  values (v_org_id, v_booking.id, v_user_id, p_action,
          jsonb_build_object('from', v_booking.status, 'to', v_next_status));
end;
$function$;

-- Update older SECURITY DEFINER RPCs in-place, retaining their existing validation
-- and journal logic while narrowing the accepted role sets.
do $migration$
declare
  v_function record;
  v_definition text;
  v_original text;
begin
  for v_function in
    select p.oid, p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = any (array[
        'add_payroll_employee', 'create_monthly_payroll_run', 'update_payroll_employee',
        'update_payroll_item', 'payroll_run_action',
        'create_manual_journal', 'finance_dashboard_summary', 'record_finance_expense',
        'record_other_income',
        'save_stock_product', 'adjust_stock_balance', 'create_stock_supplier',
        'create_stock_warehouse', 'create_stock_purchase_order',
        'create_stock_purchase_order_multi', 'receive_stock_purchase_order',
        'receive_stock_purchase_order_multi',
        'issue_sales_invoice', 'record_sales_payment',
        'create_sales_recovery_task', 'update_sales_recovery_task'
      ])
  loop
    v_definition := pg_get_functiondef(v_function.oid);
    v_original := v_definition;

    -- Payroll administration is owner/admin only.
    if v_function.proname in (
      'add_payroll_employee', 'create_monthly_payroll_run', 'update_payroll_employee',
      'update_payroll_item', 'payroll_run_action'
    ) then
      v_definition := regexp_replace(
        v_definition,
        $$role in \('owner','admin','manager','accountant'\)$$,
        $$role in ('owner','admin')$$,
        'gi'
      );
    end if;

    -- Company-wide finance and journal operations are owner/admin/accountant.
    if v_function.proname in ('create_manual_journal', 'finance_dashboard_summary') then
      v_definition := regexp_replace(
        v_definition,
        $$role in \('owner','admin','manager','accountant'\)$$,
        $$role in ('owner','admin','accountant')$$,
        'gi'
      );
    elsif v_function.proname in ('record_finance_expense', 'record_other_income') then
      v_definition := regexp_replace(
        v_definition,
        $$role in \('owner','admin','accountant','manager'\)$$,
        $$role in ('owner','admin','accountant')$$,
        'gi'
      );
      v_definition := regexp_replace(
        v_definition,
        $$role in \('owner','admin','manager','accountant'\)$$,
        $$role in ('owner','admin','accountant')$$,
        'gi'
      );
    end if;

    -- Stock, warehouse and purchasing mutations are owner/admin/manager.
    if v_function.proname in (
      'save_stock_product', 'adjust_stock_balance', 'create_stock_supplier',
      'create_stock_warehouse', 'create_stock_purchase_order',
      'create_stock_purchase_order_multi', 'receive_stock_purchase_order',
      'receive_stock_purchase_order_multi'
    ) then
      v_definition := regexp_replace(
        v_definition,
        $$role in \('owner','admin','manager','staff'\)$$,
        $$role in ('owner','admin','manager')$$,
        'gi'
      );

      -- Older single-line purchase RPCs predate explicit role guards.
      if v_function.proname in ('create_stock_purchase_order', 'receive_stock_purchase_order')
         and position('role in (' in lower(v_definition)) = 0 then
        v_definition := replace(
          v_definition,
          'if v_user_id is null then raise exception ''Please sign in first.''; end if;',
          'if v_user_id is null then raise exception ''Please sign in first.''; end if; ' ||
          'if not exists(select 1 from public.memberships where organization_id=v_org_id and user_id=v_user_id and role in (''owner'',''admin'',''manager'')) then raise exception ''You do not have stock management permission.''; end if;'
        );
      end if;
    end if;

    -- Sales and recovery remain available to owner/admin/manager/accountant,
    -- not general employees.
    if v_function.proname in (
      'issue_sales_invoice', 'record_sales_payment',
      'create_sales_recovery_task', 'update_sales_recovery_task'
    ) then
      v_definition := regexp_replace(
        v_definition,
        $$role in \('owner','admin','manager','accountant','staff'\)$$,
        $$role in ('owner','admin','manager','accountant')$$,
        'gi'
      );
    end if;

    -- Exact replacements cover the compact SQL formatting used by older RPCs.
    -- Keep these alongside the whitespace-tolerant patterns above.
    if v_function.proname in (
      'add_payroll_employee', 'create_monthly_payroll_run', 'update_payroll_employee',
      'update_payroll_item', 'payroll_run_action'
    ) then
      v_definition := replace(v_definition,
        'role in (''owner'',''admin'',''manager'',''accountant'')',
        'role in (''owner'',''admin'')');
    end if;

    if v_function.proname in ('create_manual_journal', 'finance_dashboard_summary') then
      v_definition := replace(v_definition,
        'role in (''owner'',''admin'',''manager'',''accountant'')',
        'role in (''owner'',''admin'',''accountant'')');
    elsif v_function.proname in ('record_finance_expense', 'record_other_income') then
      v_definition := replace(v_definition,
        'role in (''owner'',''admin'',''accountant'',''manager'')',
        'role in (''owner'',''admin'',''accountant'')');
      v_definition := replace(v_definition,
        'role in (''owner'',''admin'',''manager'',''accountant'')',
        'role in (''owner'',''admin'',''accountant'')');
    end if;

    if v_function.proname in (
      'save_stock_product', 'adjust_stock_balance', 'create_stock_supplier',
      'create_stock_warehouse', 'create_stock_purchase_order',
      'create_stock_purchase_order_multi', 'receive_stock_purchase_order',
      'receive_stock_purchase_order_multi'
    ) then
      v_definition := replace(v_definition,
        'role in (''owner'',''admin'',''manager'',''staff'')',
        'role in (''owner'',''admin'',''manager'')');
    end if;

    if v_function.proname in (
      'issue_sales_invoice', 'record_sales_payment',
      'create_sales_recovery_task', 'update_sales_recovery_task'
    ) then
      v_definition := replace(v_definition,
        'role in (''owner'',''admin'',''manager'',''accountant'',''staff'')',
        'role in (''owner'',''admin'',''manager'',''accountant'')');
    end if;

    -- Handle both common compact lookup forms as well as the regex form below.
    v_definition := replace(v_definition,
      'select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;',
      'v_org_id := public.supplyos_current_organization_id();');
    v_definition := replace(v_definition,
      'select m.organization_id into v_org_id from public.memberships m where m.user_id=v_user_id limit 1;',
      'v_org_id := public.supplyos_current_organization_id();');

    -- All RPCs using the old LIMIT 1 organization lookup now fail closed if
    -- the signed-in account has multiple workspace memberships.
    v_definition := regexp_replace(
      v_definition,
      $$select[[:space:]]+(m\.)?organization_id[[:space:]]+into[[:space:]]+v_org_id[[:space:]]+from[[:space:]]+public\.memberships[[:space:]]+(m[[:space:]]+)?where[[:space:]]+(m\.)?user_id[[:space:]]*=[[:space:]]*v_user_id[[:space:]]+limit[[:space:]]+1;$$,
      $$v_org_id := public.supplyos_current_organization_id();$$,
      'gi'
    );

    if v_definition <> v_original then
      execute v_definition;
    end if;
  end loop;
end;
$migration$;

-- Shift tracking is available to manager and staff accounts. The manager and
-- employee must explicitly start a shift and grant native location permission.
create or replace function public.start_employee_location_shift(p_consent_version text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_name text;
  v_session uuid;
begin
  if v_user is null then raise exception 'Please sign in before starting location sharing.'; end if;
  if p_consent_version is null or length(trim(p_consent_version)) < 3 or length(p_consent_version) > 80 then
    raise exception 'Explicit location consent is required.';
  end if;

  v_org := public.supplyos_current_organization_id();

  if not exists (
    select 1 from public.memberships m
    where m.organization_id = v_org
      and m.user_id = v_user
      and m.role in ('manager', 'staff')
  ) then
    raise exception 'Only managers and employees can start a work-shift location session.';
  end if;

  if exists(select 1 from public.employee_location_sessions s where s.user_id = v_user and s.ended_at is null) then
    raise exception 'A work-shift location session is already active on this account.';
  end if;
  if exists(select 1 from public.dispatch_tracking_sessions s where s.driver_user_id = v_user and s.ended_at is null) then
    raise exception 'An old delivery tracking session is still active. Contact the factory owner before starting a shift.';
  end if;

  select coalesce(nullif(trim(p.full_name), ''), 'Employee ' || left(v_user::text, 8))
    into v_name
  from public.profiles p
  where p.id = v_user;
  if v_name is null then v_name := 'Employee ' || left(v_user::text, 8); end if;

  insert into public.employee_location_sessions(organization_id, user_id, employee_name, consent_version)
  values(v_org, v_user, v_name, p_consent_version)
  returning id into v_session;

  return jsonb_build_object(
    'session_id', v_session,
    'organization_id', v_org,
    'employee_name', v_name,
    'started_at', now(),
    'consent_version', p_consent_version
  );
end;
$function$;

-- Only owner/admin can inspect or remotely stop team location sessions.
create or replace function public.admin_stop_employee_location_shift(
  p_session_id uuid,
  p_reason text default 'owner_stopped'
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user uuid := auth.uid();
  v_session public.employee_location_sessions%rowtype;
begin
  if v_user is null then raise exception 'Please sign in first.'; end if;

  select * into v_session
  from public.employee_location_sessions s
  where s.id = p_session_id
    and s.ended_at is null
    and exists (
      select 1 from public.memberships m
      where m.organization_id = s.organization_id
        and m.user_id = v_user
        and m.role in ('owner', 'admin')
    )
  for update;

  if not found then raise exception 'Active team session not found or you do not have permission.'; end if;

  update public.employee_location_sessions
  set ended_at = now(), stop_reason = left(coalesce(p_reason, 'owner_stopped'), 80)
  where id = v_session.id;

  return jsonb_build_object('stopped', true, 'session_id', v_session.id, 'ended_at', now());
end;
$function$;

-- RLS: employee booking visibility is creator-scoped; managers and owners see
-- their entire factory. Direct status updates are disabled; state transitions
-- go through the permission-checked booking_action RPC.
drop policy if exists bookings_read_org on public.bookings;
create policy bookings_read_org
on public.bookings for select to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = bookings.organization_id
      and m.user_id = (select auth.uid())
      and (
        m.role in ('owner', 'admin', 'manager')
        or (m.role = 'staff' and bookings.created_by = (select auth.uid()))
      )
  )
);

drop policy if exists bookings_update_pending_org on public.bookings;

drop policy if exists booking_items_read_org on public.booking_items;
create policy booking_items_read_org
on public.booking_items for select to authenticated
using (
  exists (
    select 1
    from public.bookings b
    join public.memberships m on m.organization_id = b.organization_id
    where b.id = booking_items.booking_id
      and m.user_id = (select auth.uid())
      and (
        m.role in ('owner', 'admin', 'manager')
        or (m.role = 'staff' and b.created_by = (select auth.uid()))
      )
  )
);

drop policy if exists booking_events_read_org on public.booking_events;
create policy booking_events_read_org
on public.booking_events for select to authenticated
using (
  exists (
    select 1
    from public.bookings b
    join public.memberships m on m.organization_id = b.organization_id
    where b.id = booking_events.booking_id
      and m.user_id = (select auth.uid())
      and (
        m.role in ('owner', 'admin', 'manager')
        or (m.role = 'staff' and b.created_by = (select auth.uid()))
      )
  )
);

-- Owner/admin-only team location access. A user can still read their own active
-- session so their app can resume the current workday after a restart.
drop policy if exists employee_location_sessions_read_authorized on public.employee_location_sessions;
create policy employee_location_sessions_read_authorized
on public.employee_location_sessions for select to authenticated
using (
  user_id = (select auth.uid())
  or exists (
    select 1 from public.memberships m
    where m.organization_id = employee_location_sessions.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin')
  )
);

-- Financial ledger/expenses are owner/admin/accountant. Managers no longer get
-- company P&L or expense visibility. Payroll and employee salary profiles are
-- restricted to owner/admin.
drop policy if exists accounting_journals_read_org on public.accounting_journal_entries;
create policy accounting_journals_read_org
on public.accounting_journal_entries for select to authenticated
using (organization_id in (
  select m.organization_id from public.memberships m
  where m.user_id = (select auth.uid()) and m.role in ('owner', 'admin', 'accountant')
));

drop policy if exists accounting_lines_read_org on public.accounting_journal_lines;
create policy accounting_lines_read_org
on public.accounting_journal_lines for select to authenticated
using (organization_id in (
  select m.organization_id from public.memberships m
  where m.user_id = (select auth.uid()) and m.role in ('owner', 'admin', 'accountant')
));

drop policy if exists finance_expenses_read_org on public.finance_expenses;
create policy finance_expenses_read_org
on public.finance_expenses for select to authenticated
using (organization_id in (
  select m.organization_id from public.memberships m
  where m.user_id = (select auth.uid()) and m.role in ('owner', 'admin', 'accountant')
));

drop policy if exists payroll_runs_read_org on public.payroll_runs;
create policy payroll_runs_read_org
on public.payroll_runs for select to authenticated
using (organization_id in (
  select m.organization_id from public.memberships m
  where m.user_id = (select auth.uid()) and m.role in ('owner', 'admin')
));

drop policy if exists payroll_items_read_org on public.payroll_items;
create policy payroll_items_read_org
on public.payroll_items for select to authenticated
using (organization_id in (
  select m.organization_id from public.memberships m
  where m.user_id = (select auth.uid()) and m.role in ('owner', 'admin')
));

drop policy if exists employees_read_org on public.employees;
create policy employees_read_org
on public.employees for select to authenticated
using (organization_id in (
  select m.organization_id from public.memberships m
  where m.user_id = (select auth.uid()) and m.role in ('owner', 'admin')
));

-- The manager and employee booking forms need shop/product lookup. Employees
-- may read the catalogue but cannot edit stock, costs, suppliers or warehouses.
drop policy if exists products_insert_org on public.products;
create policy products_insert_org
on public.products for insert to authenticated
with check (organization_id in (
  select m.organization_id from public.memberships m
  where m.user_id = (select auth.uid()) and m.role in ('owner', 'admin', 'manager')
));

drop policy if exists products_update_org on public.products;
create policy products_update_org
on public.products for update to authenticated
using (organization_id in (
  select m.organization_id from public.memberships m
  where m.user_id = (select auth.uid()) and m.role in ('owner', 'admin', 'manager')
))
with check (organization_id in (
  select m.organization_id from public.memberships m
  where m.user_id = (select auth.uid()) and m.role in ('owner', 'admin', 'manager')
));

drop policy if exists stock_movements_read_org on public.stock_movements;
create policy stock_movements_read_org
on public.stock_movements for select to authenticated
using (organization_id in (
  select m.organization_id from public.memberships m
  where m.user_id = (select auth.uid()) and m.role in ('owner', 'admin', 'manager')
));

drop policy if exists warehouses_read_org on public.warehouses;
create policy warehouses_read_org
on public.warehouses for select to authenticated
using (organization_id in (
  select m.organization_id from public.memberships m
  where m.user_id = (select auth.uid()) and m.role in ('owner', 'admin', 'manager')
));

drop policy if exists suppliers_read_org on public.suppliers;
create policy suppliers_read_org
on public.suppliers for select to authenticated
using (organization_id in (
  select m.organization_id from public.memberships m
  where m.user_id = (select auth.uid()) and m.role in ('owner', 'admin', 'manager')
));

drop policy if exists purchase_orders_read_org on public.purchase_orders;
create policy purchase_orders_read_org
on public.purchase_orders for select to authenticated
using (organization_id in (
  select m.organization_id from public.memberships m
  where m.user_id = (select auth.uid()) and m.role in ('owner', 'admin', 'manager')
));

drop policy if exists purchase_order_items_read_org on public.purchase_order_items;
create policy purchase_order_items_read_org
on public.purchase_order_items for select to authenticated
using (
  exists (
    select 1 from public.purchase_orders po
    join public.memberships m on m.organization_id = po.organization_id
    where po.id = purchase_order_items.purchase_order_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

-- Sales, invoices and collections are visible to owner/admin/manager/accountant.
-- General employees cannot read company-wide receivables or payment history.
drop policy if exists sales_invoices_read_org on public.sales_invoices;
create policy sales_invoices_read_org
on public.sales_invoices for select to authenticated
using (organization_id in (
  select m.organization_id from public.memberships m
  where m.user_id = (select auth.uid()) and m.role in ('owner', 'admin', 'manager', 'accountant')
));

drop policy if exists sales_payments_read_org on public.sales_payments;
create policy sales_payments_read_org
on public.sales_payments for select to authenticated
using (organization_id in (
  select m.organization_id from public.memberships m
  where m.user_id = (select auth.uid()) and m.role in ('owner', 'admin', 'manager', 'accountant')
));

drop policy if exists sales_recovery_tasks_read_org on public.sales_recovery_tasks;
create policy sales_recovery_tasks_read_org
on public.sales_recovery_tasks for select to authenticated
using (organization_id in (
  select m.organization_id from public.memberships m
  where m.user_id = (select auth.uid()) and m.role in ('owner', 'admin', 'manager', 'accountant')
));

-- Narrow the manager's privileged route access too: team location viewing is
-- owner/admin-only, and the application no longer exposes dispatch/truck pages.
revoke all on function public.create_booking(uuid, uuid, numeric, text) from public, anon;
grant execute on function public.create_booking(uuid, uuid, numeric, text) to authenticated;
revoke all on function public.booking_action(uuid, text) from public, anon;
grant execute on function public.booking_action(uuid, text) to authenticated;

revoke all on function public.start_employee_location_shift(text) from public, anon;
grant execute on function public.start_employee_location_shift(text) to authenticated;
revoke all on function public.admin_stop_employee_location_shift(uuid, text) from public, anon;
grant execute on function public.admin_stop_employee_location_shift(uuid, text) to authenticated;

-- Indexes for the new creator-scoped booking list and manager/owner team views.
create index if not exists bookings_org_creator_created_at_idx
  on public.bookings (organization_id, created_by, created_at desc);
create index if not exists sales_recovery_tasks_org_assigned_status_idx
  on public.sales_recovery_tasks (organization_id, assigned_to, status, due_date);

