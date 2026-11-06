-- Treat browser/device GPS as verified GPS rather than a manual coordinate edit.
-- Only trusted fixes (<= 150 m reported accuracy) advance delivery stop geofences.
create or replace function public.set_dispatch_truck_gps_location(
  p_truck_id uuid,
  p_latitude numeric,
  p_longitude numeric,
  p_accuracy_m numeric,
  p_recorded_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_org_id uuid;
  v_truck public.dispatch_trucks%rowtype;
  v_stop record;
  v_distance numeric;
  v_state text;
  v_previous text;
  v_new_count integer := 0;
  v_server_time timestamptz := now();
begin
  if v_user_id is null then
    raise exception 'Please sign in before sending GPS.';
  end if;
  if p_latitude is null or p_longitude is null
     or p_latitude < -90 or p_latitude > 90
     or p_longitude < -180 or p_longitude > 180 then
    raise exception 'Invalid GPS coordinates.';
  end if;
  if p_accuracy_m is null or p_accuracy_m < 0 or p_accuracy_m > 10000 then
    raise exception 'Invalid GPS accuracy; request a fresh device fix.';
  end if;
  if p_recorded_at is null
     or p_recorded_at > v_server_time + interval '30 seconds'
     or p_recorded_at < v_server_time - interval '30 seconds' then
    raise exception 'GPS fix is older than 30 seconds or has an invalid timestamp; wait for a fresh fix.';
  end if;

  select t.* into v_truck
    from public.dispatch_trucks t
    where t.id = p_truck_id
      and exists (
        select 1 from public.memberships m
        where m.organization_id = t.organization_id
          and m.user_id = v_user_id
          and lower(btrim(m.role)) in ('owner', 'admin', 'manager', 'dispatcher')
      )
    for update;
  if not found then
    raise exception 'Truck not found in this workspace, or your role cannot share fleet GPS.';
  end if;
  v_org_id := v_truck.organization_id;

  update public.dispatch_trucks
     set current_latitude = p_latitude,
         current_longitude = p_longitude,
         current_location_accuracy_m = p_accuracy_m,
         location_source = 'phone_gps',
         location_updated_at = v_server_time,
         updated_at = v_server_time
   where id = p_truck_id and organization_id = v_org_id;

  -- An imprecise GPS fix is retained for diagnostics and the map, but must not be
  -- treated as proof that a truck entered or left a customer geofence.
  if p_accuracy_m <= 150 then
    for v_stop in
      select l.id as load_id, l.geofence_radius_m, b.id as booking_id, b.latitude, b.longitude
        from public.dispatch_loads l
        join public.dispatch_load_bookings lb on lb.load_id = l.id
        join public.bookings b on b.id = lb.booking_id
       where l.organization_id = v_org_id
         and l.assigned_truck_id = p_truck_id
         and l.status = 'in_transit'
         and b.latitude is not null
         and b.longitude is not null
    loop
      v_distance := 6371000 * 2 * asin(sqrt(least(1,
        power(sin(radians((v_stop.latitude - p_latitude)::float8 / 2)), 2)
        + cos(radians(p_latitude::float8)) * cos(radians(v_stop.latitude::float8))
        * power(sin(radians((v_stop.longitude - p_longitude)::float8 / 2)), 2)
      )));
      v_state := case
        when v_distance <= v_stop.geofence_radius_m then 'inside'
        when v_distance <= v_stop.geofence_radius_m + 500 then 'nearby'
        else 'outside'
      end;

      select s.state into v_previous
        from public.dispatch_geofence_states s
       where s.load_id = v_stop.load_id and s.booking_id = v_stop.booking_id
       for update;

      insert into public.dispatch_geofence_states
        (organization_id, load_id, booking_id, state, distance_m, radius_m, last_checked_at)
      values
        (v_org_id, v_stop.load_id, v_stop.booking_id, v_state, round(v_distance, 2), v_stop.geofence_radius_m, v_server_time)
      on conflict (load_id, booking_id) do update
        set state = excluded.state,
            distance_m = excluded.distance_m,
            radius_m = excluded.radius_m,
            last_checked_at = excluded.last_checked_at;

      if v_previous is distinct from v_state then
        insert into public.dispatch_geofence_events
          (organization_id, load_id, booking_id, truck_id, previous_state, new_state, distance_m)
        values
          (v_org_id, v_stop.load_id, v_stop.booking_id, p_truck_id, v_previous, v_state, round(v_distance, 2));
        v_new_count := v_new_count + 1;
      end if;
    end loop;
  end if;

  insert into public.dispatch_events (organization_id, actor_id, action, details)
  values (
    v_org_id,
    v_user_id,
    'truck_gps_location_updated',
    jsonb_build_object(
      'truck_id', p_truck_id,
      'latitude', p_latitude,
      'longitude', p_longitude,
      'accuracy_m', p_accuracy_m,
      'recorded_at', p_recorded_at,
      'server_received_at', v_server_time,
      'trusted_for_geofences', p_accuracy_m <= 150,
      'geofence_transitions', v_new_count
    )
  );

  return jsonb_build_object(
    'accepted', true,
    'truck_id', p_truck_id,
    'location_updated_at', v_server_time,
    'accuracy_m', p_accuracy_m,
    'trusted_for_geofences', p_accuracy_m <= 150,
    'geofence_transitions', v_new_count
  );
end;
$$;

revoke all on function public.set_dispatch_truck_gps_location(uuid, numeric, numeric, numeric, timestamptz) from public, anon;
grant execute on function public.set_dispatch_truck_gps_location(uuid, numeric, numeric, numeric, timestamptz) to authenticated;
