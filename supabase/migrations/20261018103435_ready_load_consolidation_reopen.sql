-- Extend the existing safe planner so a fresh, factory-side ready truck can be reused.
-- A ready load is reopened and its cargo + truck inspection checks are invalidated, then
-- warehouse staff must complete loading and the truck pass again before departure.
alter function public.create_dispatch_plan_smart(uuid[],text,integer,numeric,numeric,date)
  rename to create_dispatch_plan_smart_planned_only;
revoke all on function public.create_dispatch_plan_smart_planned_only(uuid[],text,integer,numeric,numeric,date) from public,anon,authenticated;

create or replace function public.create_dispatch_plan_smart(
  p_booking_ids uuid[],p_grouping_mode text,p_capacity_orders integer default 10,p_capacity_kg numeric default 0,
  p_planned_distance_km numeric default 0,p_planned_delivery_date date default null
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_user_id uuid:=auth.uid(); v_org_id uuid; v_result jsonb; v_booking record; v_source record; v_target record;
  v_weight numeric; v_moved integer:=0; v_reopened integer:=0; v_pass_id uuid; v_old_pass_no text; v_new_pass_no text; v_old_bill_pass_no text; v_snapshot jsonb;
  v_new_load_count integer:=0; v_new_assigned integer:=0; v_grouped_count integer:=0; v_mode text:=lower(coalesce(p_grouping_mode,'city'));
  v_checklist jsonb:='{"quantities_verified":false,"packages_checked":false,"cargo_secured":false,"documents_ready":false}'::jsonb;
  v_truck_checklist jsonb:='{"tyres_checked":false,"brakes_checked":false,"lights_checked":false,"mirrors_checked":false,"horn_reverse_checked":false,"fire_extinguisher_checked":false,"documents_checked":false,"cargo_secured":false}'::jsonb;
begin
  if v_user_id is null then raise exception 'Please sign in first.'; end if;
  select m.organization_id into v_org_id from public.memberships m where m.user_id=v_user_id limit 1;
  if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;

  -- First consolidate onto untouched planned routes.
  v_result:=public.create_dispatch_plan_smart_planned_only(p_booking_ids,p_grouping_mode,p_capacity_orders,p_capacity_kg,p_planned_distance_km,p_planned_delivery_date);

  -- Then use spare capacity on ready loads only when the assigned vehicle has a fresh GPS fix
  -- inside the shared factory gate radius or the 500 m nearby buffer.
  for v_booking in
    select b.id,b.city,b.region,b.province,b.district,b.tehsil,b.area,b.zone,b.latitude,b.longitude,b.booking_no
    from public.bookings b where b.id=any(p_booking_ids) and b.organization_id=v_org_id
    order by b.province,b.region,b.district,b.tehsil,b.city,b.booking_no
  loop
    select l.id into v_source
    from public.dispatch_load_bookings lb join public.dispatch_loads l on l.id=lb.load_id
    where lb.booking_id=v_booking.id and l.organization_id=v_org_id and l.created_at=transaction_timestamp() and l.status='planned'
    limit 1;
    if v_source.id is null then continue; end if;

    select coalesce(sum(bi.quantity*p.unit_weight_kg),0) into v_weight
    from public.booking_items bi join public.products p on p.id=bi.product_id where bi.booking_id=v_booking.id;

    select l.id,l.status,l.loading_status,l.booking_count,l.estimated_weight_kg,l.planned_distance_km,
      t.id as truck_id,t.capacity_orders,t.capacity_kg,t.cost_per_km,
      case when exists(select 1 from public.dispatch_load_bookings lbx join public.bookings bx on bx.id=lbx.booking_id
        where lbx.load_id=l.id and nullif(trim(coalesce(bx.city,'')),'') is not null and nullif(trim(coalesce(v_booking.city,'')),'') is not null
          and lower(trim(bx.city))=lower(trim(v_booking.city))
          and (coalesce(trim(bx.province),'')=coalesce(trim(v_booking.province),'') or nullif(trim(coalesce(bx.province,'')),'') is null or nullif(trim(coalesce(v_booking.province,'')),'') is null)) then 0 else 1 end as route_rank
    into v_target
    from public.dispatch_loads l
    join public.dispatch_trucks t on t.id=l.assigned_truck_id
    where l.organization_id=v_org_id and l.created_at<transaction_timestamp()
      and ((l.status='planned' and l.loading_status='not_started') or (l.status='ready' and l.loading_status='loaded'))
      and t.status='available' and l.assigned_truck_id is not null
      and l.booking_count+1<=t.capacity_orders
      and (t.capacity_kg=0 or coalesce(l.estimated_weight_kg,0)+v_weight<=t.capacity_kg)
      and (l.status<>'ready' or (
        t.factory_geofence_state in ('inside','nearby')
        and t.location_source in ('phone_gps','hardware_gps')
        and t.current_location_accuracy_m is not null and t.current_location_accuracy_m <= 150
        and t.location_updated_at is not null and t.location_updated_at>=now()-interval '2 minutes'
        and exists(select 1 from public.organizations o where o.id=l.organization_id and o.factory_latitude is not null and o.factory_longitude is not null)
      ))
      and exists(select 1 from public.dispatch_load_bookings lbx join public.bookings bx on bx.id=lbx.booking_id
        where lbx.load_id=l.id and (
          (nullif(trim(coalesce(bx.city,'')),'') is not null and nullif(trim(coalesce(v_booking.city,'')),'') is not null
            and lower(trim(bx.city))=lower(trim(v_booking.city))
            and (coalesce(trim(bx.province),'')=coalesce(trim(v_booking.province),'') or nullif(trim(coalesce(bx.province,'')),'') is null or nullif(trim(coalesce(v_booking.province,'')),'') is null)) or
          (nullif(trim(coalesce(v_booking.district,'')),'') is not null and nullif(trim(coalesce(bx.district,'')),'') is not null
            and lower(trim(bx.district))=lower(trim(v_booking.district))
            and lower(trim(coalesce(bx.province,'')))=lower(trim(coalesce(v_booking.province,'')))
            and nullif(trim(coalesce(v_booking.province,'')),'') is not null) or
          (v_booking.latitude is not null and v_booking.longitude is not null and bx.latitude is not null and bx.longitude is not null and
            6371000*2*asin(sqrt(least(1,power(sin(radians((bx.latitude-v_booking.latitude)::float8/2)),2)+
              cos(radians(v_booking.latitude::float8))*cos(radians(bx.latitude::float8))*power(sin(radians((bx.longitude-v_booking.longitude)::float8/2)),2))))<=25000)
        ))
      and not exists(select 1 from public.dispatch_loads other where other.assigned_truck_id=t.id and other.id<>l.id and other.status not in ('delivered','cancelled'))
    order by route_rank asc,(t.capacity_orders-l.booking_count) asc,l.created_at asc
    limit 1 for update of l,t skip locked;

    if v_target.id is null then continue; end if;
    update public.dispatch_load_bookings set load_id=v_target.id where booking_id=v_booking.id and load_id=v_source.id;
    if not found then continue; end if;

    if v_target.status='ready' then
      select p.pass_no into v_old_pass_no from public.dispatch_truck_passes p where p.load_id=v_target.id;
      select p.bill_pass_no into v_old_bill_pass_no from public.dispatch_bill_passes p where p.load_id=v_target.id;
      update public.dispatch_loads set status='planned',loading_status='not_started',loading_started_at=null,loaded_at=null,
        loading_checklist=v_checklist,
        loading_notes=left(concat_ws(E'\n',nullif(trim(coalesce(loading_notes,'')),''),'Reopened automatically after route consolidation. Load the added booking, then repeat the loading checklist and truck inspection before dispatch.'),2000),
        updated_at=now()
      where id=v_target.id;
      v_reopened:=v_reopened+1;
    end if;

    perform public.supplyos_refresh_dispatch_load_manifest(v_target.id);
    perform public.supplyos_refresh_dispatch_load_manifest(v_source.id);

    if v_target.status='ready' then
      v_snapshot:=coalesce(public.supplyos_truck_pass_snapshot(v_target.id),'{}'::jsonb);
      insert into public.dispatch_truck_passes(organization_id,load_id,truck_id,pass_no,status,checklist,inspection_snapshot,inspection_notes,issued_by,issued_at,checked_by,checked_at,updated_at)
      values(v_org_id,v_target.id,v_target.truck_id,
        'TP-'||to_char(now(),'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6)),
        'inspection_pending',v_truck_checklist,v_snapshot,'',v_user_id,now(),null,null,now())
      on conflict(load_id) do update set truck_id=excluded.truck_id,pass_no=excluded.pass_no,status='inspection_pending',checklist=excluded.checklist,
        inspection_snapshot=excluded.inspection_snapshot,inspection_notes='',issued_by=excluded.issued_by,issued_at=now(),checked_by=null,checked_at=null,updated_at=now()
      returning id,pass_no into v_pass_id,v_new_pass_no;
      if v_old_bill_pass_no is not null then
        insert into public.dispatch_events(organization_id,load_id,actor_id,action,details)
        values(v_org_id,v_target.id,v_user_id,'bill_pass_marked_stale_after_route_consolidation',jsonb_build_object('previous_bill_pass_no',v_old_bill_pass_no,'booking_id',v_booking.id,'reason','Manifest changed; issue a fresh bill pass after reloading and re-clearing the truck inspection.'));
      end if;
      insert into public.dispatch_events(organization_id,load_id,actor_id,action,details)
      values(v_org_id,v_target.id,v_user_id,'ready_load_reopened_for_additional_booking',jsonb_build_object('booking_id',v_booking.id,'previous_truck_pass_no',v_old_pass_no,'new_truck_pass_no',v_new_pass_no,'truck_id',v_target.truck_id,'reason','Capacity and similar route matched; truck GPS fresh and at the factory geofence; loading and inspection must be repeated'));
    end if;

    -- Existing printed manifests are refreshed on the next Bill Pass action; record the invalidation now.
    insert into public.dispatch_events(organization_id,load_id,actor_id,action,details)
    values(v_org_id,v_target.id,v_user_id,'booking_consolidated_into_existing_route',jsonb_build_object('booking_id',v_booking.id,'source_load_id',v_source.id,'truck_id',v_target.truck_id,
      'reopened_for_loading',v_target.status='ready','reason','Compatible known geography with spare order/payload capacity; never consolidates into a truck already in transit'));
    v_moved:=v_moved+1;
  end loop;

  select count(*),count(*) filter(where l.assigned_truck_id is not null) into v_new_load_count,v_new_assigned
  from public.dispatch_loads l where l.organization_id=v_org_id and l.created_by=v_user_id and l.created_at=transaction_timestamp() and l.status='planned';
  v_grouped_count:=coalesce((v_result->>'consolidated_bookings')::integer,0)+v_moved;
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object('load_count',v_new_load_count,'assigned_trucks',v_new_assigned,
    'booking_count',cardinality(p_booking_ids),'grouping_mode',v_mode,'consolidated_bookings',v_grouped_count,
    'reopened_ready_routes',v_reopened,'existing_routes_extended',v_grouped_count>0);
end; $$;
revoke all on function public.create_dispatch_plan_smart(uuid[],text,integer,numeric,numeric,date) from public,anon;
grant execute on function public.create_dispatch_plan_smart(uuid[],text,integer,numeric,numeric,date) to authenticated;

-- Rebuild a bill pass if its recorded manifest has changed since it was issued.
create or replace function public.issue_dispatch_bill_pass(p_load_id uuid)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_user_id uuid:=auth.uid(); v_org_id uuid; v_load public.dispatch_loads%rowtype;
  v_existing uuid; v_existing_no text; v_existing_snapshot jsonb; v_pass_id uuid; v_snapshot jsonb; v_new_no text;
begin
  if v_user_id is null then raise exception 'Please sign in first.'; end if;
  select m.organization_id into v_org_id from public.memberships m where m.user_id=v_user_id limit 1;
  select * into v_load from public.dispatch_loads where id=p_load_id and organization_id=v_org_id for update;
  if not found then raise exception 'Load not found in this workspace.'; end if;
  if v_load.status not in ('ready','in_transit') then raise exception 'A bill pass can only be issued after loading is complete.'; end if;
  if v_load.assigned_truck_id is null then raise exception 'Assign a truck before issuing a bill pass.'; end if;
  select jsonb_build_object(
    'load',jsonb_build_object('id',l.id,'load_no',l.load_no,'destination_summary',l.destination_summary,'grouping_mode',l.grouping_mode,
      'booking_count',l.booking_count,'estimated_weight_kg',l.estimated_weight_kg,'planned_delivery_date',l.planned_delivery_date,
      'planned_distance_km',l.planned_distance_km,'estimated_cost',l.estimated_cost,'departed_at',l.departed_at,'created_at',l.created_at,
      'notes',l.notes,'stop_plan',l.stop_plan,'geofence_radius_m',l.geofence_radius_m),
    'truck',jsonb_build_object('registration_no',t.registration_no,'display_name',t.display_name,'driver_name',t.driver_name,
      'driver_phone',t.driver_phone,'current_city',t.current_city),
    'orders',coalesce((select jsonb_agg(jsonb_build_object(
       'booking_no',b.booking_no,'booking_date',b.booking_date,'order_value',b.total_amount,
       'customer_name',c.name,'customer_code',c.customer_code,'phone',c.phone,
       'address',b.delivery_address,'city',b.city,'region',b.region,'province',b.province,
       'district',b.district,'tehsil',b.tehsil,'area',b.area,'zone',b.zone,
       'items',coalesce((select jsonb_agg(jsonb_build_object('name',p.name,'sku',p.sku,'quantity',bi.quantity,'unit',p.unit) order by p.name)
         from public.booking_items bi join public.products p on p.id=bi.product_id where bi.booking_id=b.id),'[]'::jsonb)
     ) order by lb.stop_order,b.booking_no)
     from public.dispatch_load_bookings lb join public.bookings b on b.id=lb.booking_id
     join public.customers c on c.id=b.customer_id where lb.load_id=l.id),'[]'::jsonb),
    'notice','Dispatch manifest only. It is not a government permit or substitute for legally required transport documents.'
  ) into v_snapshot
  from public.dispatch_loads l join public.dispatch_trucks t on t.id=l.assigned_truck_id where l.id=p_load_id;

  select id,bill_pass_no,content_snapshot into v_existing,v_existing_no,v_existing_snapshot
  from public.dispatch_bill_passes where load_id=p_load_id;
  if v_existing is not null and v_existing_snapshot is not distinct from v_snapshot then return v_existing; end if;
  if v_existing is not null then
    v_new_no:='BP-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
    update public.dispatch_bill_passes set bill_pass_no=v_new_no,content_snapshot=v_snapshot,issued_by=v_user_id,issued_at=now() where id=v_existing;
    insert into public.dispatch_events(organization_id,load_id,actor_id,action,details)
    values(v_org_id,p_load_id,v_user_id,'bill_pass_regenerated_after_manifest_change',jsonb_build_object('previous_bill_pass_no',v_existing_no,'new_bill_pass_no',v_new_no,'reason','Load manifest changed; previous printed copy should be treated as superseded'));
    return v_existing;
  end if;
  insert into public.dispatch_bill_passes(organization_id,load_id,content_snapshot,issued_by)
  values(v_org_id,p_load_id,v_snapshot,v_user_id) returning id into v_pass_id;
  insert into public.dispatch_events(organization_id,load_id,actor_id,action,details)
  values(v_org_id,p_load_id,v_user_id,'bill_pass_issued',jsonb_build_object('bill_pass_id',v_pass_id));
  return v_pass_id;
end; $$;
revoke all on function public.issue_dispatch_bill_pass(uuid) from public,anon;
grant execute on function public.issue_dispatch_bill_pass(uuid) to authenticated;
