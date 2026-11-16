-- Role-based SupplyOS release 1.
-- Booking writes remain transactional, but the SECURITY DEFINER entry points now
-- enforce the same owner / manager / employee permissions as the applications.

drop policy if exists bookings_read_org on public.bookings;
create policy bookings_read_by_role on public.bookings
for select to authenticated
using (
  exists (
    select 1
    from public.memberships m
    where m.organization_id = bookings.organization_id
      and m.user_id = (select auth.uid())
      and (
        m.role in ('owner', 'admin', 'manager')
        or (m.role = 'staff' and bookings.created_by = (select auth.uid()))
      )
  )
);

-- Application writes are performed by narrowly-authorized SECURITY DEFINER RPCs.
-- Remove the older broad pending-row update policy to prevent direct client edits.
drop policy if exists bookings_update_pending_org on public.bookings;

drop policy if exists employee_location_sessions_read_authorized on public.employee_location_sessions;
create policy employee_location_sessions_read_authorized on public.employee_location_sessions
for select to authenticated
using (
  user_id = (select auth.uid())
  or exists (
    select 1
    from public.memberships m
    where m.organization_id = employee_location_sessions.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin')
  )
);

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
  if v_user_id is null then
    raise exception 'Please sign in first.';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be greater than zero.';
  end if;
  if p_notes is not null and length(p_notes) > 2000 then
    raise exception 'Booking notes are too long.';
  end if;

  -- Resolve the workspace from the selected shop rather than an arbitrary
  -- membership row, so multi-workspace users cannot cross organization data.
  select * into v_customer
  from public.customers
  where id = p_customer_id and status = 'active'
  for update;
  if not found then
    raise exception 'Choose an active shop from your factory.';
  end if;
  v_org_id := v_customer.organization_id;

  select m.role into v_role
  from public.memberships m
  where m.organization_id = v_org_id and m.user_id = v_user_id
  limit 1;
  if not found then
    raise exception 'You do not have access to this factory shop.';
  end if;
  if v_role not in ('owner', 'admin', 'manager', 'staff') then
    raise exception 'Your role cannot create bookings.';
  end if;

  select * into v_product
  from public.products
  where id = p_product_id
    and organization_id = v_org_id
    and is_active = true;
  if not found then
    raise exception 'Choose an active product from your factory.';
  end if;

  insert into public.bookings (
    organization_id, customer_id, city, region, score_snapshot, notes, created_by
  )
  values (
    v_org_id, v_customer.id, v_customer.city, v_customer.region,
    v_customer.score, coalesce(p_notes, ''), v_user_id
  )
  returning id into v_booking_id;

  insert into public.booking_items (
    booking_id, product_id, quantity, unit_price, unit_cost
  )
  values (
    v_booking_id, v_product.id, p_quantity, v_product.unit_price, v_product.unit_cost
  );

  insert into public.booking_events (organization_id, booking_id, actor_id, action, details)
  values (
    v_org_id, v_booking_id, v_user_id, 'created',
    jsonb_build_object('quantity', p_quantity, 'product_id', p_product_id)
  );

  return v_booking_id;
end;
$function$;

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
  if v_user_id is null then
    raise exception 'Please sign in first.';
  end if;

  select b.* into v_booking
  from public.bookings b
  where b.id = p_booking_id
  for update;
  if not found then
    raise exception 'Booking was not found.';
  end if;
  v_org_id := v_booking.organization_id;

  select m.role into v_role
  from public.memberships m
  where m.organization_id = v_org_id
    and m.user_id = v_user_id
  limit 1;
  if not found then
    raise exception 'You do not have access to this factory booking.';
  end if;

  if p_action in ('approve', 'reject') and v_role not in ('owner', 'admin') then
    raise exception 'Only the owner can approve or reject bookings.';
  elsif p_action = 'complete' and v_role not in ('owner', 'admin', 'manager') then
    raise exception 'Only an owner or manager can complete an approved booking.';
  elsif p_action = 'cancel' then
    if v_role not in ('owner', 'admin', 'manager')
      and not (v_role = 'staff' and v_booking.created_by = v_user_id
        and v_booking.status = 'pending_approval') then
      raise exception 'You can only cancel your own pending booking.';
    end if;
  elsif p_action not in ('approve', 'reject', 'cancel', 'complete') then
    raise exception 'Unsupported booking action.';
  end if;

  if p_action = 'approve' then
    if v_booking.status <> 'pending_approval' then
      raise exception 'Only pending bookings can be approved.';
    end if;

    select * into v_customer
    from public.customers
    where id = v_booking.customer_id
      and organization_id = v_org_id
    for update;
    if not found then
      raise exception 'Shop record was not found.';
    end if;
    if v_customer.credit_used + v_booking.total_amount > v_customer.credit_limit then
      raise exception 'Credit limit exceeded. Review the shop limit or outstanding balance before approving.';
    end if;

    -- Lock products before checking and reserving stock to prevent overselling.
    for v_item in
      select i.product_id, i.quantity
      from public.booking_items i
      where i.booking_id = v_booking.id
      order by i.product_id
    loop
      select (p.stock_on_hand - p.stock_reserved) into v_available
      from public.products p
      where p.id = v_item.product_id
        and p.organization_id = v_org_id
      for update;
      if not found then
        raise exception 'A product in this booking is no longer available.';
      end if;
      if v_available < v_item.quantity then
        raise exception 'Insufficient available stock for one or more items.';
      end if;
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
    if v_booking.status <> 'pending_approval' then
      raise exception 'Only pending bookings can be rejected.';
    end if;
    v_next_status := 'rejected';
    update public.bookings set status = v_next_status, updated_at = now()
    where id = v_booking.id;

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
    update public.bookings set status = v_next_status, updated_at = now()
    where id = v_booking.id;

  elsif p_action = 'complete' then
    if v_booking.status <> 'approved' then
      raise exception 'Only approved bookings can be completed.';
    end if;
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
      if not found then
        raise exception 'Stock changed unexpectedly. Refresh inventory and try again.';
      end if;
    end loop;
    v_next_status := 'completed';
    update public.bookings set status = v_next_status, updated_at = now()
    where id = v_booking.id;
  end if;

  insert into public.booking_events (organization_id, booking_id, actor_id, action, details)
  values (
    v_org_id, v_booking.id, v_user_id, p_action,
    jsonb_build_object('from', v_booking.status, 'to', v_next_status)
  );
end;
$function$;

revoke all on function public.create_booking(uuid, uuid, numeric, text) from public, anon;
grant execute on function public.create_booking(uuid, uuid, numeric, text) to authenticated;
revoke all on function public.booking_action(uuid, text) from public, anon;
grant execute on function public.booking_action(uuid, text) to authenticated;

-- Only employee and manager accounts start work-shift location sessions.
-- Owners view team locations from the owner app; they do not need to track themselves.
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
  if v_user is null then
    raise exception 'Please sign in before starting location sharing.';
  end if;
  if p_consent_version is null
    or length(trim(p_consent_version)) < 3
    or length(p_consent_version) > 80 then
    raise exception 'Explicit employee location consent is required.';
  end if;

  select m.organization_id into v_org
  from public.memberships m
  where m.user_id = v_user and m.role in ('staff', 'manager')
  order by m.created_at asc
  limit 1;
  if v_org is null then
    raise exception 'Only employee and manager accounts can start work-shift location sharing.';
  end if;

  if exists (
    select 1 from public.employee_location_sessions s
    where s.user_id = v_user and s.ended_at is null
  ) then
    raise exception 'A work-shift location session is already active on this account.';
  end if;

  select coalesce(nullif(trim(p.full_name), ''), 'Employee ' || left(v_user::text, 8))
  into v_name
  from public.profiles p
  where p.id = v_user;
  if v_name is null then
    v_name := 'Employee ' || left(v_user::text, 8);
  end if;

  insert into public.employee_location_sessions (
    organization_id, user_id, employee_name, consent_version
  )
  values (v_org, v_user, v_name, p_consent_version)
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

revoke all on function public.start_employee_location_shift(text) from public, anon;
grant execute on function public.start_employee_location_shift(text) to authenticated;

create index if not exists employee_location_sessions_org_active_fresh_idx
  on public.employee_location_sessions (organization_id, last_location_at desc)
  where ended_at is null;
