-- Employees need safe booking and shop catalogue data, not raw rows containing
-- customer credit limits, product costs, margins, and internal score snapshots.
-- Read access for employees is therefore moved to narrow SECURITY DEFINER RPCs.

drop policy if exists customers_read_org on public.customers;
create policy customers_read_owner_manager on public.customers
for select to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = customers.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

drop policy if exists products_read_org on public.products;
create policy products_read_owner_manager on public.products
for select to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = products.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

drop policy if exists bookings_read_by_role on public.bookings;
create policy bookings_read_owner_manager on public.bookings
for select to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = bookings.organization_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

drop policy if exists booking_items_read_org on public.booking_items;
create policy booking_items_read_owner_manager on public.booking_items
for select to authenticated
using (
  exists (
    select 1
    from public.bookings b
    join public.memberships m on m.organization_id = b.organization_id
    where b.id = booking_items.booking_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

drop policy if exists booking_events_read_by_role on public.booking_events;
create policy booking_events_read_owner_manager on public.booking_events
for select to authenticated
using (
  exists (
    select 1
    from public.bookings b
    join public.memberships m on m.organization_id = b.organization_id
    where b.id = booking_events.booking_id
      and m.user_id = (select auth.uid())
      and m.role in ('owner', 'admin', 'manager')
  )
);

create or replace function public.get_booking_catalog()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_shops jsonb;
  v_products jsonb;
begin
  if v_user is null then raise exception 'Please sign in first.'; end if;

  select m.organization_id, m.role into v_org, v_role
  from public.memberships m
  where m.user_id = v_user
  order by m.created_at asc
  limit 1;

  if v_org is null or v_role not in ('owner', 'admin', 'manager', 'staff') then
    raise exception 'Your account does not have booking catalogue access.';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', c.id,
      'customer_code', c.customer_code,
      'name', c.name,
      'city', c.city,
      'region', c.region
    ) order by c.name
  ), '[]'::jsonb)
  into v_shops
  from (
    select id, customer_code, name, city, region
    from public.customers
    where organization_id = v_org and status = 'active'
    order by name
    limit 1000
  ) c;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', p.id,
      'sku', p.sku,
      'name', p.name,
      'unit', p.unit,
      'unit_price', p.unit_price,
      'stock_on_hand', p.stock_on_hand,
      'stock_reserved', p.stock_reserved
    ) order by p.name
  ), '[]'::jsonb)
  into v_products
  from (
    select id, sku, name, unit, unit_price, stock_on_hand, stock_reserved
    from public.products
    where organization_id = v_org and is_active = true
    order by name
    limit 1000
  ) p;

  return jsonb_build_object('shops', v_shops, 'products', v_products);
end;
$function$;

create or replace function public.get_my_bookings()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_result jsonb;
begin
  if v_user is null then raise exception 'Please sign in first.'; end if;

  select m.organization_id, m.role into v_org, v_role
  from public.memberships m
  where m.user_id = v_user
  order by m.created_at asc
  limit 1;

  if v_org is null or v_role <> 'staff' then
    raise exception 'This employee booking list is only available to employee accounts.';
  end if;

  select coalesce(jsonb_agg(to_jsonb(q)), '[]'::jsonb)
  into v_result
  from (
    select
      b.id,
      b.booking_no,
      b.booking_date,
      b.status,
      b.total_amount,
      b.city,
      b.region,
      b.notes,
      b.created_at,
      jsonb_build_object('name', c.name, 'customer_code', c.customer_code) as customers,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'quantity', bi.quantity,
          'products', jsonb_build_object('name', p.name, 'sku', p.sku)
        ))
        from public.booking_items bi
        join public.products p on p.id = bi.product_id
        where bi.booking_id = b.id
      ), '[]'::jsonb) as booking_items
    from public.bookings b
    left join public.customers c on c.id = b.customer_id
    where b.organization_id = v_org
      and b.created_by = v_user
    order by b.created_at desc
    limit 500
  ) q;

  return v_result;
end;
$function$;

create or replace function public.get_my_booking_detail(p_booking_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_role text;
  v_result jsonb;
begin
  if v_user is null then raise exception 'Please sign in first.'; end if;

  select m.organization_id, m.role into v_org, v_role
  from public.memberships m
  where m.user_id = v_user
  order by m.created_at asc
  limit 1;

  if v_org is null or v_role <> 'staff' then
    raise exception 'This employee booking detail is only available to employee accounts.';
  end if;

  select jsonb_build_object(
    'id', b.id,
    'booking_no', b.booking_no,
    'booking_date', b.booking_date,
    'status', b.status,
    'total_amount', b.total_amount,
    'city', b.city,
    'region', b.region,
    'notes', b.notes,
    'created_at', b.created_at,
    'customers', jsonb_build_object('name', c.name, 'customer_code', c.customer_code),
    'booking_items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'quantity', bi.quantity,
        'unit_price', bi.unit_price,
        'line_total', bi.line_total,
        'products', jsonb_build_object('name', p.name, 'sku', p.sku, 'unit', p.unit)
      ))
      from public.booking_items bi
      join public.products p on p.id = bi.product_id
      where bi.booking_id = b.id
    ), '[]'::jsonb),
    'booking_events', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id,
        'action', e.action,
        'details', e.details,
        'created_at', e.created_at
      ) order by e.created_at desc)
      from public.booking_events e
      where e.booking_id = b.id
    ), '[]'::jsonb)
  )
  into v_result
  from public.bookings b
  join public.customers c on c.id = b.customer_id
  where b.id = p_booking_id
    and b.organization_id = v_org
    and b.created_by = v_user;

  if v_result is null then raise exception 'Booking not found in your employee account.'; end if;
  return v_result;
end;
$function$;

revoke all on function public.get_booking_catalog() from public, anon;
grant execute on function public.get_booking_catalog() to authenticated;
revoke all on function public.get_my_bookings() from public, anon;
grant execute on function public.get_my_bookings() to authenticated;
revoke all on function public.get_my_booking_detail(uuid) from public, anon;
grant execute on function public.get_my_booking_detail(uuid) to authenticated;
