-- Keep high-level dashboard and booking analytics inside Postgres.
-- This avoids transferring large monthly booking/product lists to the browser
-- (or to the Next.js server) solely to calculate summary cards and charts.

create index if not exists bookings_org_booking_date_idx
  on public.bookings (organization_id, booking_date desc);

create index if not exists sales_invoices_org_issue_date_idx
  on public.sales_invoices (organization_id, issue_date desc);

create index if not exists dispatch_load_bookings_load_stop_idx
  on public.dispatch_load_bookings (load_id, stop_order);

create index if not exists customers_org_active_idx
  on public.customers (organization_id)
  where status = 'active';

create index if not exists products_org_low_stock_idx
  on public.products (organization_id, name)
  include (id, sku, stock_on_hand, stock_reserved)
  where is_active and stock_on_hand <= stock_reserved;

create or replace function public.supplyos_dashboard_summary(
  p_month_start date,
  p_today date
)
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with accessible_orgs as materialized (
    select m.organization_id
    from public.memberships as m
    where m.user_id = (select auth.uid())
  ),
  month_rows as materialized (
    select b.booking_date, b.status, b.total_amount
    from public.bookings as b
    where b.organization_id in (select organization_id from accessible_orgs)
      and b.booking_date >= p_month_start
      and b.booking_date < (p_month_start + interval '1 month')::date
  ),
  booking_metrics as (
    select
      count(*)::bigint as order_count,
      count(*) filter (where status in ('approved', 'completed'))::bigint as approved_count,
      count(*) filter (where status = 'cancelled')::bigint as cancelled_count,
      coalesce(sum(total_amount), 0)::numeric as total_value,
      coalesce(sum(total_amount) filter (where status in ('approved', 'completed')), 0)::numeric as approved_value,
      coalesce(sum(total_amount) filter (where status = 'cancelled'), 0)::numeric as cancelled_value,
      count(*) filter (where booking_date = p_today)::bigint as today_count
    from month_rows
  ),
  daily_metrics as (
    select coalesce(
      jsonb_agg(jsonb_build_object('booking_date', d.booking_date, 'count', d.booking_count) order by d.booking_date),
      '[]'::jsonb
    ) as daily_counts
    from (
      select booking_date, count(*)::bigint as booking_count
      from month_rows
      group by booking_date
    ) as d
  ),
  queue_metrics as (
    select
      (select count(*)::bigint from public.bookings b
       where b.organization_id in (select organization_id from accessible_orgs)
         and b.status = 'pending_approval') as pending_count,
      (select count(*)::bigint from public.customers c
       where c.organization_id in (select organization_id from accessible_orgs)
         and c.status = 'active') as customer_count
  ),
  stock_metrics as (
    select
      count(*)::bigint as low_stock_count,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', top_products.id,
          'name', top_products.name,
          'sku', top_products.sku,
          'stock_on_hand', top_products.stock_on_hand,
          'stock_reserved', top_products.stock_reserved
        ) order by top_products.name)
        from (
          select p.id, p.name, p.sku, p.stock_on_hand, p.stock_reserved
          from public.products as p
          where p.organization_id in (select organization_id from accessible_orgs)
            and p.is_active
            and p.stock_on_hand <= p.stock_reserved
          order by p.name
          limit 3
        ) as top_products
      ), '[]'::jsonb) as low_stock_products
    from public.products as p
    where p.organization_id in (select organization_id from accessible_orgs)
      and p.is_active
      and p.stock_on_hand <= p.stock_reserved
  )
  select jsonb_build_object(
    'order_count', bm.order_count,
    'approved_count', bm.approved_count,
    'cancelled_count', bm.cancelled_count,
    'total_value', bm.total_value,
    'approved_value', bm.approved_value,
    'cancelled_value', bm.cancelled_value,
    'today_count', bm.today_count,
    'daily_counts', dm.daily_counts,
    'pending_count', qm.pending_count,
    'customer_count', qm.customer_count,
    'low_stock_count', sm.low_stock_count,
    'low_stock_products', sm.low_stock_products
  )
  from booking_metrics as bm
  cross join daily_metrics as dm
  cross join queue_metrics as qm
  cross join stock_metrics as sm;
$$;

revoke all on function public.supplyos_dashboard_summary(date, date) from public;
grant execute on function public.supplyos_dashboard_summary(date, date) to authenticated;
