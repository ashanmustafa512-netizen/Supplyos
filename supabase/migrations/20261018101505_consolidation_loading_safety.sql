-- Prevent automatic consolidation from changing a load that has already started physical loading.
-- Only untouched, planned loads may receive another booking. Match known geography conservatively.
create or replace function public.create_dispatch_plan_smart(
  p_booking_ids uuid[],p_grouping_mode text,p_capacity_orders integer default 10,p_capacity_kg numeric default 0,
  p_planned_distance_km numeric default 0,p_planned_delivery_date date default null
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_user_id uuid:=auth.uid(); v_org_id uuid; v_result jsonb; v_booking record; v_source record; v_target record;
  v_weight numeric; v_moved integer:=0; v_new_load_count integer:=0; v_new_assigned integer:=0; v_mode text:=lower(coalesce(p_grouping_mode,'city'));
begin
  if v_user_id is null then raise exception 'Please sign in first.'; end if;
  select m.organization_id into v_org_id from public.memberships m where m.user_id=v_user_id limit 1;
  if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
  v_result:=public.create_dispatch_plan(p_booking_ids,p_grouping_mode,p_capacity_orders,p_capacity_kg,p_planned_distance_km,p_planned_delivery_date);
  for v_booking in
    select b.id,b.city,b.region,b.province,b.district,b.tehsil,b.area,b.zone,b.latitude,b.longitude,b.booking_no
    from public.bookings b where b.id=any(p_booking_ids) and b.organization_id=v_org_id
    order by b.province,b.region,b.district,b.tehsil,b.city,b.booking_no
  loop
    select l.id,l.created_at,l.booking_count into v_source
    from public.dispatch_load_bookings lb join public.dispatch_loads l on l.id=lb.load_id
    where lb.booking_id=v_booking.id and l.organization_id=v_org_id and l.created_at=transaction_timestamp()
    limit 1;
    if v_source.id is null then continue; end if;
    select coalesce(sum(bi.quantity*p.unit_weight_kg),0) into v_weight
    from public.booking_items bi join public.products p on p.id=bi.product_id where bi.booking_id=v_booking.id;
    select l.id,l.booking_count,l.estimated_weight_kg,l.planned_distance_km,t.id as truck_id,t.capacity_orders,t.capacity_kg,t.cost_per_km,
      case when exists(select 1 from public.dispatch_load_bookings lbx join public.bookings bx on bx.id=lbx.booking_id
        where lbx.load_id=l.id and nullif(trim(coalesce(bx.city,'')),'') is not null and nullif(trim(coalesce(v_booking.city,'')),'') is not null
          and lower(trim(bx.city))=lower(trim(v_booking.city))
          and (coalesce(trim(bx.province),'')=coalesce(trim(v_booking.province),'') or nullif(trim(coalesce(bx.province,'')),'') is null or nullif(trim(coalesce(v_booking.province,'')),'') is null)) then 0 else 1 end as route_rank
    into v_target
    from public.dispatch_loads l join public.dispatch_trucks t on t.id=l.assigned_truck_id
    where l.organization_id=v_org_id and l.created_at<transaction_timestamp() and l.status='planned'
      and l.loading_status='not_started' and t.status='available' and l.assigned_truck_id is not null
      and l.booking_count+1<=t.capacity_orders
      and (t.capacity_kg=0 or coalesce(l.estimated_weight_kg,0)+v_weight<=t.capacity_kg)
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
    if v_target.id is not null then
      update public.dispatch_load_bookings set load_id=v_target.id where booking_id=v_booking.id and load_id=v_source.id;
      if found then
        perform public.supplyos_refresh_dispatch_load_manifest(v_source.id);
        perform public.supplyos_refresh_dispatch_load_manifest(v_target.id);
        insert into public.dispatch_events(organization_id,load_id,actor_id,action,details)
        values(v_org_id,v_target.id,v_user_id,'booking_consolidated_into_existing_route',jsonb_build_object('booking_id',v_booking.id,'source_load_id',v_source.id,'truck_id',v_target.truck_id,'reason','Compatible known geography and available payload/order capacity; route loading had not started'));
        v_moved:=v_moved+1;
      end if;
    end if;
  end loop;
  for v_source in select l.id from public.dispatch_loads l where l.organization_id=v_org_id and l.created_by=v_user_id and l.created_at=transaction_timestamp()
    and exists(select 1 from public.dispatch_load_bookings lb where lb.load_id=l.id) loop
    perform public.supplyos_refresh_dispatch_load_manifest(v_source.id);
  end loop;
  select count(*),count(*) filter(where l.assigned_truck_id is not null) into v_new_load_count,v_new_assigned
  from public.dispatch_loads l where l.organization_id=v_org_id and l.created_by=v_user_id and l.created_at=transaction_timestamp() and l.status='planned';
  return jsonb_build_object('load_count',v_new_load_count,'assigned_trucks',v_new_assigned,'booking_count',cardinality(p_booking_ids),
    'grouping_mode',v_mode,'consolidated_bookings',v_moved,'existing_routes_extended',v_moved>0);
end; $$;
revoke all on function public.create_dispatch_plan_smart(uuid[],text,integer,numeric,numeric,date) from public,anon;
grant execute on function public.create_dispatch_plan_smart(uuid[],text,integer,numeric,numeric,date) to authenticated;
