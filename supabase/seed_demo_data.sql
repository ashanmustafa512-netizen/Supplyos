-- SupplyOS demo seed: 100 customers, 40 SKUs, 200 bookings, 25 trucks,
-- 24 dispatch loads, six targets, and audit events.
-- Safe to rerun: only records carrying the DEMO- prefix / DEMO marker are replaced.
-- Run this in Supabase SQL Editor for the SupplyOS project. Do not run against production business data.
begin;
do $seed$
declare
  v_org uuid;
  v_owner uuid;
  v_city_idx integer;
  v_customer_idx integer;
  v_product_idx integer;
  v_product_idx_2 integer;
  v_booking_idx integer;
  v_load_idx integer;
  v_start_idx integer;
  v_end_idx integer;
  v_truck_idx integer;
  v_booking_id uuid;
  v_truck_id uuid;
  v_load_id uuid;
  v_status text;
  v_city text;
  v_region text;
  v_province text;
  v_district text;
  v_tehsil text;
  v_area text;
  v_zone text;
  v_delivery_at timestamptz;
  v_departed_at timestamptz;
  v_planned_date date;
  v_weight numeric;
  v_distance numeric;
  v_cost numeric;
  v_stop_plan jsonb;
  v_cities text[] := array[
    'Lahore','Karachi','Hyderabad','Islamabad','Rawalpindi','Faisalabad','Gujranwala','Multan','Peshawar','Quetta',
    'Sialkot','Sargodha','Bahawalpur','Sukkur','Abbottabad','Mardan','Sahiwal','Jhelum','Rahim Yar Khan','Gwadar'
  ];
  v_products text[] := array[
    'Corrugated Carton - Small','Corrugated Carton - Large','Stretch Wrap Roll','Packing Tape - Clear','Industrial Safety Gloves',
    'PPE Safety Goggles','Steel Fastener Pack','PVC Pipe - 1 inch','PVC Pipe - 2 inch','Copper Cable Roll',
    'Industrial Lubricant - 1L','Industrial Lubricant - 5L','Cleaning Liquid - 1L','Cleaning Powder - 5kg','Food-grade Plastic Crate',
    'Reusable Storage Bin','Paper Ream - A4','Thermal Label Roll','Barcode Label Pack','Pallet - Standard',
    'Bubble Wrap Roll','Foam Sheet Pack','Aluminium Profile Bundle','Metal Bracket Set','Rubber Seal Pack',
    'Water Filter Cartridge','Pump Spare Kit','Electric Motor - Small','LED Work Light','Cable Tie Pack',
    'Hand Tool Kit','Welding Rod Pack','Protective Apron','Floor Cleaner - 5L','Desiccant Pack',
    'Stretch Film Dispenser','Pallet Strap Roll','Shipping Envelope Pack','Fastener Assortment Box','Warehouse Marking Tape'
  ];
  v_suffix text;
begin
  select o.id, o.owner_id into v_org, v_owner
  from public.organizations o
  join public.memberships m on m.organization_id = o.id and m.user_id = o.owner_id
  order by o.created_at desc limit 1;
  if v_org is null or v_owner is null then
    raise exception 'No owned SupplyOS organization found. Sign up / create a workspace first.';
  end if;

  -- Remove only the previous generated demo dataset in this workspace.
  delete from public.dispatch_events where organization_id = v_org and (details ->> 'demo_seed' = 'true' or action like 'DEMO%');
  delete from public.dispatch_loads where organization_id = v_org and load_no like 'DEMO-LD-%';
  delete from public.dispatch_targets where organization_id = v_org and name like 'DEMO - %';
  delete from public.bookings where organization_id = v_org and booking_no like 'DEMO-BK-%';
  delete from public.dispatch_trucks where organization_id = v_org and registration_no like 'DEMO-TRK-%';
  delete from public.customers where organization_id = v_org and customer_code like 'DEMO-CUST-%';
  delete from public.products where organization_id = v_org and sku like 'DEMO-SKU-%';

  -- 100 B2B customers: five outlets for each of twenty destinations.
  for i in 1..100 loop
    v_city_idx := ((i - 1) / 5) + 1;
    v_city := v_cities[v_city_idx];
    v_province := case
      when v_city in ('Karachi','Hyderabad','Sukkur') then 'Sindh'
      when v_city in ('Peshawar','Mardan','Abbottabad') then 'Khyber Pakhtunkhwa'
      when v_city = 'Quetta' or v_city = 'Gwadar' then 'Balochistan'
      when v_city = 'Islamabad' then 'Islamabad Capital Territory'
      else 'Punjab'
    end;
    v_region := case
      when v_province = 'Sindh' then 'Sindh Distribution'
      when v_province = 'Khyber Pakhtunkhwa' then 'North-West Distribution'
      when v_province = 'Balochistan' then 'Western Distribution'
      when v_province = 'Islamabad Capital Territory' then 'Capital Distribution'
      when v_city in ('Multan','Bahawalpur','Rahim Yar Khan','Sahiwal') then 'South Punjab Distribution'
      when v_city in ('Sialkot','Gujranwala','Jhelum','Sargodha','Faisalabad') then 'Central / North Punjab Distribution'
      else 'Metro Distribution'
    end;
    v_district := case when v_city = 'Islamabad' then 'Islamabad' when v_city = 'Karachi' then 'Karachi' else v_city end;
    v_tehsil := case when v_city in ('Karachi','Lahore','Islamabad','Rawalpindi') then 'Central ' || v_city else v_city end;
    v_area := 'Industrial Area ' || (((i - 1) % 5) + 1)::text;
    v_zone := 'Zone ' || (((i - 1) % 8) + 1)::text;
    insert into public.customers (
      organization_id, customer_code, name, city, region, province, district, tehsil, area, zone,
      delivery_address, phone, credit_limit, credit_used, score, status
    ) values (
      v_org, 'DEMO-CUST-' || lpad(i::text, 3, '0'),
      'DEMO - ' || ((array['Al Noor Traders','Crescent Wholesale','Metro Supply House','Prime Retail Depot','Unity General Store'])[((i - 1) % 5) + 1]) || ' - ' || v_city || ' ' || lpad(i::text, 3, '0'),
      v_city, v_region, v_province, v_district, v_tehsil, v_area, v_zone,
      'Demo Warehouse ' || (((i - 1) % 12) + 1)::text || ', ' || v_area || ', ' || v_city,
      '+92-300-' || lpad((1000000 + i * 7919)::text, 7, '0'),
      (750000 + (i % 8) * 250000)::numeric, 0, 55 + ((i * 13) % 45), 'active'
    );
  end loop;

  -- 40 SKUs with realistic demo prices, weights and starting inventory.
  for i in 1..40 loop
    v_suffix := lpad(i::text, 3, '0');
    insert into public.products (
      organization_id, sku, name, unit, unit_cost, unit_price, stock_on_hand, stock_reserved, unit_weight_kg, is_active
    ) values (
      v_org, 'DEMO-SKU-' || v_suffix, v_products[i],
      case when i in (1,2,7,15,16,24,25,31,32,38,39) then 'pack' when i in (8,9,10,11,12,13,14,17,18,19,21,22,26,29,34,35,36,37,40) then 'roll / unit' else 'unit' end,
      (100 + ((i * 233) % 2800))::numeric,
      round((100 + ((i * 233) % 2800))::numeric * (1.18 + ((i % 7) * 0.035)), 2),
      10000, 0, round((0.3 + (((i * 7) % 26) * 0.25))::numeric, 3), true
    );
  end loop;

  -- 200 bookings spanning useful operational states and the last two months.
  for i in 1..200 loop
    v_customer_idx := ((i - 1) / 2) + 1;
    v_status := case
      when i <= 40 then 'completed'
      when i <= 140 then 'approved'
      when i <= 170 then 'pending_approval'
      when i <= 190 then 'rejected'
      else 'cancelled'
    end;
    insert into public.bookings (
      organization_id, booking_no, customer_id, booking_date, city, region, province, district, tehsil,
      area, zone, delivery_address, status, score_snapshot, notes, created_by, approved_by, approved_at
    )
    select v_org, 'DEMO-BK-' || lpad(i::text, 4, '0'), c.id,
      current_date - ((i * 3) % 60), c.city, c.region, c.province, c.district, c.tehsil,
      c.area, c.zone, c.delivery_address, v_status::public.booking_status, c.score,
      'DEMO DATA - Generated dispatch workflow booking #' || lpad(i::text, 4, '0'), v_owner,
      case when v_status in ('approved','completed') then v_owner else null end,
      case when v_status in ('approved','completed') then now() - ((i % 12) || ' hours')::interval else null end
    from public.customers c
    where c.organization_id = v_org and c.customer_code = 'DEMO-CUST-' || lpad(v_customer_idx::text, 3, '0');
  end loop;

  -- Two products per booking; the normal booking-total trigger derives the money totals.
  for i in 1..200 loop
    v_product_idx := (((i - 1) * 3) % 40) + 1;
    v_product_idx_2 := (((i * 7 + 10) % 40) + 1);
    if v_product_idx_2 = v_product_idx then v_product_idx_2 := (v_product_idx_2 % 40) + 1; end if;
    select id into v_booking_id from public.bookings where organization_id = v_org and booking_no = 'DEMO-BK-' || lpad(i::text, 4, '0');
    insert into public.booking_items (booking_id, product_id, quantity, unit_price, unit_cost)
    select v_booking_id, p.id, (5 + ((i * 7) % 21))::numeric, p.unit_price, p.unit_cost
    from public.products p where p.organization_id = v_org and p.sku = 'DEMO-SKU-' || lpad(v_product_idx::text, 3, '0');
    insert into public.booking_items (booking_id, product_id, quantity, unit_price, unit_cost)
    select v_booking_id, p.id, (3 + ((i * 11) % 16))::numeric, p.unit_price, p.unit_cost
    from public.products p where p.organization_id = v_org and p.sku = 'DEMO-SKU-' || lpad(v_product_idx_2::text, 3, '0');
  end loop;

  -- Inventory remains reconcilable: completed quantities are consumed; approved quantities stay reserved.
  update public.products p set
    stock_reserved = coalesce((
      select sum(bi.quantity) from public.booking_items bi join public.bookings b on b.id = bi.booking_id
      where bi.product_id = p.id and b.organization_id = v_org and b.status = 'approved'
    ), 0),
    stock_on_hand = greatest(10000 - coalesce((
      select sum(bi.quantity) from public.booking_items bi join public.bookings b on b.id = bi.booking_id
      where bi.product_id = p.id and b.organization_id = v_org and b.status = 'completed'
    ), 0), 1)
  where p.organization_id = v_org and p.sku like 'DEMO-SKU-%';

  -- One deliberately constrained SKU drives a visible stock-reservation warning without violating inventory checks.
  update public.products p set stock_on_hand = case
    when p.stock_reserved > 0 then greatest(p.stock_reserved + 1, ceil(p.stock_reserved / 0.87))
    else 40 end
  where p.organization_id = v_org and p.sku = 'DEMO-SKU-005';

  update public.customers c set credit_used = coalesce((
    select sum(b.total_amount) from public.bookings b
    where b.customer_id = c.id and b.organization_id = v_org and b.status in ('approved','completed')
  ), 0)
  where c.organization_id = v_org and c.customer_code like 'DEMO-CUST-%';

  insert into public.booking_events (organization_id, booking_id, actor_id, action, details, created_at)
  select v_org, b.id, v_owner, 'demo_seed_created', jsonb_build_object('demo_seed', true, 'booking_no', b.booking_no), b.created_at
  from public.bookings b where b.organization_id = v_org and b.booking_no like 'DEMO-BK-%';
  insert into public.booking_events (organization_id, booking_id, actor_id, action, details, created_at)
  select v_org, b.id, v_owner,
    case b.status when 'approved' then 'demo_seed_approved' when 'completed' then 'demo_seed_completed'
      when 'rejected' then 'demo_seed_rejected' when 'cancelled' then 'demo_seed_cancelled' else 'demo_seed_pending' end,
    jsonb_build_object('demo_seed', true, 'booking_no', b.booking_no, 'status', b.status::text),
    b.created_at + interval '15 minutes'
  from public.bookings b where b.organization_id = v_org and b.booking_no like 'DEMO-BK-%';

  -- 25 trucks: 6 currently in transit, 10 available, 4 in maintenance, 5 inactive.
  for i in 1..25 loop
    v_city_idx := ((i - 1) % 20) + 1;
    insert into public.dispatch_trucks (
      organization_id, registration_no, display_name, capacity_orders, capacity_kg, cost_per_km,
      current_city, driver_name, driver_phone, status, notes
    ) values (
      v_org, 'DEMO-TRK-' || lpad(i::text, 2, '0'),
      ((array['Hino 500','Isuzu NPR','Mazda Titan','JAC N-Series','Hyundai Mighty'])[((i - 1) % 5) + 1]) || ' / Demo Fleet ' || lpad(i::text, 2, '0'),
      8 + ((i * 3) % 9), (2500 + ((i * 617) % 6500))::numeric, (95 + ((i * 17) % 80))::numeric,
      v_cities[v_city_idx], 'Demo Driver ' || lpad(i::text, 2, '0'), '+92-301-' || lpad((2000000 + i * 6367)::text, 7, '0'),
      case when i <= 6 then 'in_transit' when i <= 16 then 'available' when i <= 20 then 'maintenance' else 'inactive' end,
      'DEMO DATA - fictional fleet record for testing'
    );
  end loop;

  -- 24 realistic load examples: 8 delivered, 6 in transit and 10 planned.
  for i in 1..24 loop
    if i <= 8 then
      v_status := 'delivered';
      v_start_idx := ((i - 1) * 5) + 1;
      v_truck_idx := 7 + ((i - 1) % 10);
      v_delivery_at := now() - ((i % 8) || ' days')::interval;
      v_departed_at := v_delivery_at - interval '8 hours';
      v_planned_date := v_delivery_at::date;
    elsif i <= 14 then
      v_status := 'in_transit';
      v_start_idx := 41 + ((i - 9) * 5);
      v_truck_idx := i - 8;
      v_delivery_at := null;
      v_departed_at := now() - (((i % 8) + 1) || ' hours')::interval;
      v_planned_date := current_date + (1 + (i % 2));
    else
      v_status := 'planned';
      v_start_idx := 71 + ((i - 15) * 5);
      v_truck_idx := case when i <= 21 then i - 8 else null end;
      v_delivery_at := null;
      v_departed_at := null;
      v_planned_date := case when i in (15,22) then current_date - 3 else current_date + (1 + (i % 4)) end;
    end if;
    v_end_idx := v_start_idx + 4;

    select b.city, b.region, b.province, b.district, b.tehsil, b.area, b.zone
      into v_city, v_region, v_province, v_district, v_tehsil, v_area, v_zone
    from public.bookings b where b.organization_id = v_org and b.booking_no = 'DEMO-BK-' || lpad(v_start_idx::text, 4, '0');
    select coalesce(sum(bi.quantity * p.unit_weight_kg),0) into v_weight
    from public.booking_items bi join public.products p on p.id = bi.product_id
    join public.bookings b on b.id = bi.booking_id
    where b.organization_id = v_org and b.booking_no between 'DEMO-BK-' || lpad(v_start_idx::text, 4, '0') and 'DEMO-BK-' || lpad(v_end_idx::text, 4, '0');
    select id into v_truck_id from public.dispatch_trucks where organization_id = v_org and registration_no = 'DEMO-TRK-' || lpad(v_truck_idx::text, 2, '0');
    v_distance := 35 + ((i * 29) % 245);
    select round(v_distance * coalesce(t.cost_per_km, 0), 2) into v_cost from public.dispatch_trucks t where t.id = v_truck_id;
    v_cost := coalesce(v_cost, 0);
    v_stop_plan := jsonb_build_array(jsonb_build_object(
      'stop_order', 1, 'province', coalesce(v_province,''), 'region', coalesce(v_region,''),
      'district', coalesce(v_district,''), 'tehsil', coalesce(v_tehsil,''), 'city', coalesce(v_city,'Unknown city'),
      'area', 'Multiple delivery areas', 'zone', 'Multiple zones', 'booking_count', 5
    ));

    insert into public.dispatch_loads (
      organization_id, load_no, grouping_mode, group_key, destination_summary, stop_plan,
      booking_count, capacity_orders, estimated_weight_kg, assigned_truck_id, status,
      planned_delivery_date, planned_distance_km, estimated_cost, notes, created_by, departed_at, delivered_at, created_at, updated_at
    ) values (
      v_org, 'DEMO-LD-' || lpad(i::text, 3, '0'), 'city', coalesce(v_city,'Destination not set'),
      coalesce(v_city,'Destination not set') || ' / ' || coalesce(v_province,''), v_stop_plan,
      5, 10, round(v_weight,3), v_truck_id, v_status,
      v_planned_date, v_distance, v_cost,
      'DEMO DATA - ' || case v_status when 'delivered' then 'completed sample route' when 'in_transit' then 'active route in transit' else 'sample planned dispatch' end,
      v_owner, v_departed_at, v_delivery_at,
      case when v_status = 'delivered' then coalesce(v_delivery_at,now()) - interval '1 day' when v_status = 'in_transit' then now() - interval '2 days' else now() - interval '1 day' end,
      coalesce(v_delivery_at, now())
    ) returning id into v_load_id;

    insert into public.dispatch_load_bookings (load_id, booking_id, stop_order, delivery_status, delivered_at)
    select v_load_id, b.id, 1,
      case when v_status = 'delivered' then 'delivered' else 'pending' end,
      case when v_status = 'delivered' then v_delivery_at else null end
    from public.bookings b
    where b.organization_id = v_org
      and b.booking_no between 'DEMO-BK-' || lpad(v_start_idx::text, 4, '0') and 'DEMO-BK-' || lpad(v_end_idx::text, 4, '0');

    insert into public.dispatch_events (organization_id, load_id, actor_id, action, details, created_at)
    values (v_org, v_load_id, v_owner, 'DEMO_LOAD_SEEDED', jsonb_build_object('demo_seed', true, 'load_no', 'DEMO-LD-' || lpad(i::text,3,'0'), 'status', v_status, 'booking_start', v_start_idx, 'booking_end', v_end_idx), coalesce(v_delivery_at, now()) - interval '1 hour');
  end loop;

  -- One intentionally unassigned / overdue route creates useful warning scenarios.
  -- Current month target is intentionally ambitious so forecasts have a non-trivial example.
  insert into public.dispatch_targets (
    organization_id, name, period_type, starts_on, ends_on, target_deliveries, target_loads, target_on_time_rate, is_active, notes, created_by
  ) values
    (v_org, 'DEMO - Weekly dispatch target', 'weekly', date_trunc('week',current_date)::date, (date_trunc('week',current_date)::date + 6), 95, 20, 96, true, 'DEMO DATA - stretch weekly target to test pace forecasting', v_owner),
    (v_org, 'DEMO - October delivery target', 'monthly', date_trunc('month',current_date)::date, (date_trunc('month',current_date) + interval '1 month - 1 day')::date, 450, 90, 94, true, 'DEMO DATA - deliberately ambitious monthly target for warning demos', v_owner),
    (v_org, 'DEMO - Quarterly fulfilment target', 'quarterly', date_trunc('quarter',current_date)::date, (date_trunc('quarter',current_date) + interval '3 months - 1 day')::date, 1400, 280, 93, true, 'DEMO DATA - quarterly delivery goal', v_owner),
    (v_org, 'DEMO - Annual fleet productivity', 'annual', make_date(extract(year from current_date)::int,1,1), make_date(extract(year from current_date)::int,12,31), 5000, 1000, 95, true, 'DEMO DATA - annual planning scenario', v_owner),
    (v_org, 'DEMO - Regional consolidation pilot', 'custom', current_date - 14, current_date + 14, 220, 44, 92, true, 'DEMO DATA - custom 29-day target for route consolidation', v_owner),
    (v_org, 'DEMO - Peak season stretch goal', 'custom', current_date - 7, current_date + 21, 700, 140, 97, true, 'DEMO DATA - stretch target for a warning/forecast scenario', v_owner);

  -- Three clearly marked contingency examples make the incident workflow easy to demo.
  insert into public.dispatch_contingencies (organization_id, load_id, reported_by, issue_type, severity, summary, notes, status, action_taken, resolved_by, resolved_at)
  select v_org, l.id, v_owner, x.issue_type, x.severity, x.summary, x.notes, x.status, x.action_taken,
    case when x.status = 'resolved' then v_owner else null end,
    case when x.status = 'resolved' then now() - interval '1 day' else null end
  from (values
    ('DEMO-LD-009','delay','high','DEMO DATA - Traffic delay on motorway','Driver reports a road queue; dispatch should contact customer with an updated ETA.','open',''),
    ('DEMO-LD-010','customer_unavailable','medium','DEMO DATA - Customer contact not responding','Driver attempted two calls. Confirm opening hours and arrange another attempt.','open',''),
    ('DEMO-LD-016','road_closure','medium','DEMO DATA - Alternate road arranged','Dispatch assigned an alternate approach and verified the next stop sequence.','resolved','Alternate route approved by dispatch; customer notified.')
  ) as x(load_no,issue_type,severity,summary,notes,status,action_taken)
  join public.dispatch_loads l on l.organization_id = v_org and l.load_no = x.load_no;

  -- Approximate city-level map points for demos only. These are not exact shop addresses.
  with city_coords(city,lat,lon) as (values
    ('Lahore',31.5204,74.3587),('Karachi',24.8607,67.0011),('Hyderabad',25.3960,68.3578),
    ('Islamabad',33.6844,73.0479),('Rawalpindi',33.5651,73.0169),('Faisalabad',31.4504,73.1350),
    ('Gujranwala',32.1877,74.1945),('Multan',30.1575,71.5249),('Peshawar',34.0151,71.5249),
    ('Quetta',30.1798,66.9750),('Sialkot',32.4945,74.5229),('Sargodha',32.0836,72.6711),
    ('Bahawalpur',29.3956,71.6836),('Sukkur',27.7052,68.8574),('Abbottabad',34.1688,73.2215),
    ('Mardan',34.1989,72.0231),('Sahiwal',30.6682,73.1114),('Jhelum',32.9425,73.7257),
    ('Rahim Yar Khan',28.4202,70.2952),('Gwadar',25.1264,62.3225)
  )
  update public.customers c set
    latitude=round((cc.lat + (((substring(c.customer_code from '[0-9]+')::integer % 9)-4)*0.0015))::numeric,7),
    longitude=round((cc.lon + ((((substring(c.customer_code from '[0-9]+')::integer*3) % 9)-4)*0.0015))::numeric,7)
  from city_coords cc where c.organization_id=v_org and c.customer_code like 'DEMO-CUST-%' and c.city=cc.city;

  -- Copy demo shop coordinates to each booking so routes have real map destinations.
  update public.bookings b set latitude=c.latitude, longitude=c.longitude
  from public.customers c
  where b.organization_id=v_org and c.organization_id=v_org and b.customer_id=c.id
    and b.booking_no like 'DEMO-BK-%' and c.customer_code like 'DEMO-CUST-%';

  -- Coherent factory-to-shop demo routes. The factory coordinate configured in Settings is
  -- the origin; six in-transit trucks are placed part-way along their own factory-to-destination
  -- line. These are clearly unverified DEMO positions (manual source), never real GPS and never
  -- eligible for the trusted-GPS dispatch consolidation gate. All other demo trucks are staged at
  -- the factory. Re-running the seed refreshes only DEMO fleet positions.
  update public.dispatch_trucks t set
    current_latitude=o.factory_latitude,
    current_longitude=o.factory_longitude,
    current_city='Factory / dispatch yard',
    current_location_accuracy_m=null,
    location_source='manual',
    location_updated_at=now(),
    notes=concat_ws(E'\n', nullif(t.notes,''), 'DEMO DATA - staged at factory; coordinates are simulated, not live GPS')
  from public.organizations o
  where t.organization_id=v_org and o.id=v_org and t.registration_no like 'DEMO-TRK-%'
    and o.factory_latitude is not null and o.factory_longitude is not null;

  with active_routes_ranked as (
    select t.id as truck_id, b.city, b.latitude as dest_lat, b.longitude as dest_lon,
      o.factory_latitude::numeric as factory_lat, o.factory_longitude::numeric as factory_lon,
      (0.25 + ((substring(l.load_no from '[0-9]+')::integer * 7) % 40) / 100.0)::numeric as progress,
      row_number() over (partition by t.id order by lb.stop_order, b.booking_no) as rn
    from public.dispatch_trucks t
    join public.dispatch_loads l on l.organization_id=t.organization_id and l.assigned_truck_id=t.id
    join public.dispatch_load_bookings lb on lb.load_id=l.id
    join public.bookings b on b.id=lb.booking_id
    join public.organizations o on o.id=t.organization_id
    where t.organization_id=v_org and t.registration_no like 'DEMO-TRK-%'
      and l.load_no like 'DEMO-LD-%' and l.status='in_transit'
      and o.factory_latitude is not null and o.factory_longitude is not null
  ), active_routes as (select * from active_routes_ranked where rn=1)
  update public.dispatch_trucks t set
    current_latitude=round((r.factory_lat + (r.dest_lat-r.factory_lat)*r.progress)::numeric,7),
    current_longitude=round((r.factory_lon + (r.dest_lon-r.factory_lon)*r.progress)::numeric,7),
    current_city='DEMO en route to ' || coalesce(r.city,'customer destination'),
    current_location_accuracy_m=null,
    location_source='manual',
    location_updated_at=now(),
    notes=concat_ws(E'\n', nullif(t.notes,''), 'DEMO DATA - simulated midpoint on factory-to-shop route; not live GPS')
  from active_routes r where t.id=r.truck_id;
end
$seed$;
commit;
