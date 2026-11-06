create or replace function public.record_employee_location(
  p_session_id uuid,p_latitude double precision,p_longitude double precision,
  p_accuracy_m double precision default null,p_recorded_at timestamptz default now()
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_user uuid:=auth.uid();
  v_session public.employee_location_sessions%rowtype;
  v_factory record;
  v_distance double precision;
  v_state text;
begin
  if v_user is null then raise exception 'Please sign in first.'; end if;
  if p_latitude is null or p_longitude is null or p_latitude < -90 or p_latitude > 90 or p_longitude < -180 or p_longitude > 180 then raise exception 'Invalid GPS coordinates.'; end if;
  if p_accuracy_m is not null and (p_accuracy_m < 0 or p_accuracy_m > 10000) then raise exception 'Invalid GPS accuracy.'; end if;
  if p_recorded_at is null or p_recorded_at > now()+interval '30 seconds' or p_recorded_at < now()-interval '5 minutes' then raise exception 'GPS fix is too old. Wait for a fresh location fix.'; end if;
  select * into v_session from public.employee_location_sessions s where s.id=p_session_id and s.user_id=v_user and s.ended_at is null for update;
  if not found then raise exception 'Employee location session is no longer active.'; end if;
  select o.factory_latitude,o.factory_longitude,o.factory_geofence_radius_m into v_factory from public.organizations o where o.id=v_session.organization_id;
  v_distance:=null; v_state:='unknown';
  if v_factory.factory_latitude is not null and v_factory.factory_longitude is not null then
    v_distance:=6371000*2*asin(sqrt(least(1,power(sin(radians((v_factory.factory_latitude-p_latitude)/2)),2)+cos(radians(p_latitude))*cos(radians(v_factory.factory_latitude))*power(sin(radians((v_factory.factory_longitude-p_longitude)/2)),2))));
    if p_accuracy_m is null or p_accuracy_m > 150 then v_state:='unknown';
    elsif v_distance <= coalesce(v_factory.factory_geofence_radius_m,250) then v_state:='inside';
    elsif v_distance <= coalesce(v_factory.factory_geofence_radius_m,250)+500 then v_state:='nearby';
    else v_state:='outside'; end if;
  end if;
  update public.employee_location_sessions
  set current_latitude=p_latitude,current_longitude=p_longitude,current_location_accuracy_m=p_accuracy_m,
      location_source='phone_gps',factory_distance_m=v_distance,factory_geofence_state=v_state,
      factory_geofence_checked_at=now(),last_location_at=p_recorded_at
  where id=v_session.id;
  return jsonb_build_object('accepted',true,'server_received_at',now(),'recorded_at',p_recorded_at,'factory_distance_m',v_distance,'factory_geofence_state',v_state);
end; $$;
revoke all on function public.record_employee_location(uuid,double precision,double precision,double precision,timestamptz) from public,anon;
grant execute on function public.record_employee_location(uuid,double precision,double precision,double precision,timestamptz) to authenticated;
