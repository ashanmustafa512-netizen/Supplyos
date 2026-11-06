-- SupplyOS MVP — initial schema, authentication bootstrap, RLS, and booking workflows.
-- Run this file in Supabase SQL Editor (or apply with the Supabase CLI).

create extension if not exists pgcrypto;

do $$ begin
  create type public.booking_status as enum ('pending_approval', 'approved', 'cancelled', 'rejected', 'completed', 'remade');
exception when duplicate_object then null; end $$;

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  currency_code text not null default 'PKR' check (char_length(currency_code) = 3),
  owner_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'owner' check (role in ('owner', 'admin', 'manager', 'staff', 'dispatcher', 'accountant')),
  created_at timestamptz not null default now(),
  unique (organization_id, user_id)
);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  customer_code text not null,
  name text not null,
  city text not null default '',
  region text not null default '',
  phone text not null default '',
  credit_limit numeric(14,2) not null default 0 check (credit_limit >= 0),
  credit_used numeric(14,2) not null default 0 check (credit_used >= 0),
  score integer not null default 75 check (score between 0 and 100),
  status text not null default 'active' check (status in ('active', 'inactive')),
  created_at timestamptz not null default now(),
  unique (organization_id, customer_code)
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  sku text not null,
  name text not null,
  unit text not null default 'unit',
  unit_cost numeric(14,2) not null default 0 check (unit_cost >= 0),
  unit_price numeric(14,2) not null default 0 check (unit_price >= 0),
  stock_on_hand numeric(14,3) not null default 0 check (stock_on_hand >= 0),
  stock_reserved numeric(14,3) not null default 0 check (stock_reserved >= 0 and stock_reserved <= stock_on_hand),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id, sku)
);

create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  booking_no text not null default ('BK-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))),
  customer_id uuid not null references public.customers(id) on delete restrict,
  booking_date date not null default current_date,
  city text not null default '',
  region text not null default '',
  status public.booking_status not null default 'pending_approval',
  total_amount numeric(14,2) not null default 0 check (total_amount >= 0),
  total_cost numeric(14,2) not null default 0 check (total_cost >= 0),
  profit numeric(14,2) generated always as (total_amount - total_cost) stored,
  score_snapshot integer not null default 75 check (score_snapshot between 0 and 100),
  notes text not null default '',
  created_by uuid not null references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, booking_no)
);

create table if not exists public.booking_items (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  unit_cost numeric(14,2) not null check (unit_cost >= 0),
  line_total numeric(14,2) generated always as (round(quantity * unit_price, 2)) stored,
  line_cost numeric(14,2) generated always as (round(quantity * unit_cost, 2)) stored,
  created_at timestamptz not null default now()
);

create table if not exists public.booking_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  booking_id uuid not null references public.bookings(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists memberships_user_id_idx on public.memberships(user_id);
create index if not exists customers_org_name_idx on public.customers(organization_id, name);
create index if not exists products_org_name_idx on public.products(organization_id, name);
create index if not exists bookings_org_created_idx on public.bookings(organization_id, created_at desc);
create index if not exists bookings_org_status_idx on public.bookings(organization_id, status);
create index if not exists booking_items_booking_idx on public.booking_items(booking_id);
create index if not exists booking_events_booking_idx on public.booking_events(booking_id, created_at desc);

-- New Supabase Auth users receive a private company workspace and owner membership.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_company_name text;
  v_full_name text;
begin
  v_company_name := nullif(trim(coalesce(new.raw_user_meta_data ->> 'company_name', '')), '');
  v_full_name := nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), '');

  insert into public.profiles (id, full_name)
  values (new.id, coalesce(v_full_name, ''))
  on conflict (id) do update set full_name = excluded.full_name;

  insert into public.organizations (name, owner_id)
  values (coalesce(v_company_name, split_part(coalesce(new.email, 'Factory'), '@', 1) || ' Factory'), new.id)
  returning id into v_org_id;

  insert into public.memberships (organization_id, user_id, role)
  values (v_org_id, new.id, 'owner');

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_supplyos on auth.users;
create trigger on_auth_user_created_supplyos
after insert on auth.users
for each row execute function public.handle_new_user();

-- Keep booking header totals derived from booking_items, never from client input.
create or replace function public.recalculate_booking_totals()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking_id uuid;
begin
  if tg_op = 'DELETE' then
    v_booking_id := old.booking_id;
  else
    v_booking_id := new.booking_id;
  end if;
  update public.bookings b
  set total_amount = coalesce((select sum(i.line_total) from public.booking_items i where i.booking_id = v_booking_id), 0),
      total_cost = coalesce((select sum(i.line_cost) from public.booking_items i where i.booking_id = v_booking_id), 0),
      updated_at = now()
  where b.id = v_booking_id;
  return null;
end;
$$;

drop trigger if exists booking_items_recalculate_totals on public.booking_items;
create trigger booking_items_recalculate_totals
after insert or update or delete on public.booking_items
for each row execute function public.recalculate_booking_totals();

-- Create a booking plus its item as one transaction. Prices/cost are read from the product record.
create or replace function public.create_booking(
  p_customer_id uuid,
  p_product_id uuid,
  p_quantity numeric,
  p_notes text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_org_id uuid;
  v_customer public.customers%rowtype;
  v_product public.products%rowtype;
  v_booking_id uuid;
begin
  if v_user_id is null then raise exception 'Please sign in first.'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be greater than zero.'; end if;

  select m.organization_id into v_org_id
  from public.memberships m where m.user_id = v_user_id limit 1;
  if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;

  select * into v_customer from public.customers
  where id = p_customer_id and organization_id = v_org_id and status = 'active'
  for update;
  if not found then raise exception 'Choose an active customer from your factory.'; end if;

  select * into v_product from public.products
  where id = p_product_id and organization_id = v_org_id and is_active = true;
  if not found then raise exception 'Choose an active product from your factory.'; end if;

  insert into public.bookings (organization_id, customer_id, city, region, score_snapshot, notes, created_by)
  values (v_org_id, v_customer.id, v_customer.city, v_customer.region, v_customer.score, coalesce(p_notes, ''), v_user_id)
  returning id into v_booking_id;

  insert into public.booking_items (booking_id, product_id, quantity, unit_price, unit_cost)
  values (v_booking_id, v_product.id, p_quantity, v_product.unit_price, v_product.unit_cost);

  insert into public.booking_events (organization_id, booking_id, actor_id, action, details)
  values (v_org_id, v_booking_id, v_user_id, 'created', jsonb_build_object('quantity', p_quantity, 'product_id', p_product_id));

  return v_booking_id;
end;
$$;

-- All approval transitions are checked transactionally in PostgreSQL.
create or replace function public.booking_action(p_booking_id uuid, p_action text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_booking public.bookings%rowtype;
  v_customer public.customers%rowtype;
  v_item record;
  v_available numeric(14,3);
  v_org_id uuid;
  v_next_status public.booking_status;
begin
  if v_user_id is null then raise exception 'Please sign in first.'; end if;

  select b.* into v_booking from public.bookings b where b.id = p_booking_id for update;
  if not found then raise exception 'Booking was not found.'; end if;
  v_org_id := v_booking.organization_id;

  if not exists (select 1 from public.memberships m where m.organization_id = v_org_id and m.user_id = v_user_id) then
    raise exception 'You do not have access to this factory booking.';
  end if;

  if p_action = 'approve' then
    if v_booking.status <> 'pending_approval' then raise exception 'Only pending bookings can be approved.'; end if;

    select * into v_customer from public.customers where id = v_booking.customer_id and organization_id = v_org_id for update;
    if not found then raise exception 'Customer record was not found.'; end if;
    if v_customer.credit_used + v_booking.total_amount > v_customer.credit_limit then
      raise exception 'Credit limit exceeded. Review the customer limit or their outstanding balance before approving.';
    end if;

    -- Lock each product row so two concurrent approvals cannot reserve the same units.
    for v_item in select i.product_id, i.quantity from public.booking_items i where i.booking_id = v_booking.id order by i.product_id loop
      select (p.stock_on_hand - p.stock_reserved) into v_available
      from public.products p
      where p.id = v_item.product_id and p.organization_id = v_org_id
      for update;
      if not found then raise exception 'A product in this booking is no longer available.'; end if;
      if v_available < v_item.quantity then raise exception 'Insufficient available stock for one or more items.'; end if;
    end loop;

    for v_item in select i.product_id, i.quantity from public.booking_items i where i.booking_id = v_booking.id loop
      update public.products set stock_reserved = stock_reserved + v_item.quantity where id = v_item.product_id and organization_id = v_org_id;
    end loop;
    update public.customers set credit_used = credit_used + v_booking.total_amount where id = v_customer.id;
    v_next_status := 'approved';
    update public.bookings set status = v_next_status, approved_by = v_user_id, approved_at = now(), updated_at = now() where id = v_booking.id;

  elsif p_action = 'reject' then
    if v_booking.status <> 'pending_approval' then raise exception 'Only pending bookings can be rejected.'; end if;
    v_next_status := 'rejected';
    update public.bookings set status = v_next_status, updated_at = now() where id = v_booking.id;

  elsif p_action = 'cancel' then
    if v_booking.status = 'completed' or v_booking.status = 'cancelled' or v_booking.status = 'rejected' then
      raise exception 'This booking can no longer be cancelled.';
    end if;
    if v_booking.status = 'approved' then
      for v_item in select i.product_id, i.quantity from public.booking_items i where i.booking_id = v_booking.id loop
        update public.products set stock_reserved = greatest(0, stock_reserved - v_item.quantity) where id = v_item.product_id and organization_id = v_org_id;
      end loop;
      update public.customers set credit_used = greatest(0, credit_used - v_booking.total_amount) where id = v_booking.customer_id and organization_id = v_org_id;
    end if;
    v_next_status := 'cancelled';
    update public.bookings set status = v_next_status, updated_at = now() where id = v_booking.id;

  elsif p_action = 'complete' then
    if v_booking.status <> 'approved' then raise exception 'Only approved bookings can be completed.'; end if;
    for v_item in select i.product_id, i.quantity from public.booking_items i where i.booking_id = v_booking.id loop
      update public.products
      set stock_on_hand = stock_on_hand - v_item.quantity,
          stock_reserved = stock_reserved - v_item.quantity
      where id = v_item.product_id and organization_id = v_org_id and stock_reserved >= v_item.quantity and stock_on_hand >= v_item.quantity;
      if not found then raise exception 'Stock changed unexpectedly. Refresh inventory and try again.'; end if;
    end loop;
    -- Customer credit remains outstanding until the Sales & Recovery module records payment.
    v_next_status := 'completed';
    update public.bookings set status = v_next_status, updated_at = now() where id = v_booking.id;

  else
    raise exception 'Unsupported booking action.';
  end if;

  insert into public.booking_events (organization_id, booking_id, actor_id, action, details)
  values (v_org_id, v_booking.id, v_user_id, p_action, jsonb_build_object('from', v_booking.status, 'to', v_next_status));
end;
$$;

-- Row Level Security: all visible operational data is scoped to a user's membership.
alter table public.organizations enable row level security;
alter table public.profiles enable row level security;
alter table public.memberships enable row level security;
alter table public.customers enable row level security;
alter table public.products enable row level security;
alter table public.bookings enable row level security;
alter table public.booking_items enable row level security;
alter table public.booking_events enable row level security;

revoke all on public.organizations, public.profiles, public.memberships, public.customers, public.products, public.bookings, public.booking_items, public.booking_events from anon;
revoke all on public.organizations, public.profiles, public.memberships, public.customers, public.products, public.bookings, public.booking_items, public.booking_events from authenticated;

grant select on public.organizations, public.profiles, public.memberships, public.customers, public.products, public.bookings, public.booking_items, public.booking_events to authenticated;
grant update (full_name) on public.profiles to authenticated;
grant insert (organization_id, customer_code, name, city, region, phone, credit_limit, score, status) on public.customers to authenticated;
grant update (customer_code, name, city, region, phone, credit_limit, score, status) on public.customers to authenticated;
grant insert (organization_id, sku, name, unit, unit_cost, unit_price, stock_on_hand, is_active) on public.products to authenticated;
grant update (sku, name, unit, unit_cost, unit_price, stock_on_hand, is_active) on public.products to authenticated;
grant update (booking_date, city, region, notes) on public.bookings to authenticated;

drop policy if exists "memberships_read_self" on public.memberships;
create policy "memberships_read_self" on public.memberships for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists "profiles_read_self" on public.profiles;
create policy "profiles_read_self" on public.profiles for select to authenticated using (id = (select auth.uid()));
drop policy if exists "profiles_update_self" on public.profiles;
create policy "profiles_update_self" on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

drop policy if exists "organizations_read_member" on public.organizations;
create policy "organizations_read_member" on public.organizations for select to authenticated using (
  exists (select 1 from public.memberships m where m.organization_id = organizations.id and m.user_id = (select auth.uid()))
);

drop policy if exists "customers_read_org" on public.customers;
create policy "customers_read_org" on public.customers for select to authenticated using (
  organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid()))
);
drop policy if exists "customers_insert_org" on public.customers;
create policy "customers_insert_org" on public.customers for insert to authenticated with check (
  organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid()))
);
drop policy if exists "customers_update_org" on public.customers;
create policy "customers_update_org" on public.customers for update to authenticated using (
  organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid()))
) with check (
  organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid()))
);

drop policy if exists "products_read_org" on public.products;
create policy "products_read_org" on public.products for select to authenticated using (
  organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid()))
);
drop policy if exists "products_insert_org" on public.products;
create policy "products_insert_org" on public.products for insert to authenticated with check (
  organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid()))
);
drop policy if exists "products_update_org" on public.products;
create policy "products_update_org" on public.products for update to authenticated using (
  organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid()))
) with check (
  organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid()))
);

drop policy if exists "bookings_read_org" on public.bookings;
create policy "bookings_read_org" on public.bookings for select to authenticated using (
  organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid()))
);
drop policy if exists "bookings_update_pending_org" on public.bookings;
create policy "bookings_update_pending_org" on public.bookings for update to authenticated using (
  status = 'pending_approval' and organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid()))
) with check (
  status = 'pending_approval' and organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid()))
);

drop policy if exists "booking_items_read_org" on public.booking_items;
create policy "booking_items_read_org" on public.booking_items for select to authenticated using (
  exists (select 1 from public.bookings b where b.id = booking_id and b.organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid())))
);

drop policy if exists "booking_events_read_org" on public.booking_events;
create policy "booking_events_read_org" on public.booking_events for select to authenticated using (
  organization_id in (select m.organization_id from public.memberships m where m.user_id = (select auth.uid()))
);

revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.recalculate_booking_totals() from public, anon, authenticated;
revoke all on function public.create_booking(uuid, uuid, numeric, text) from public, anon;
revoke all on function public.booking_action(uuid, text) from public, anon;
grant execute on function public.create_booking(uuid, uuid, numeric, text) to authenticated;
grant execute on function public.booking_action(uuid, text) to authenticated;
