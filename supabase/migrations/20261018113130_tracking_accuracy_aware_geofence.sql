create or replace function public.supplyos_refresh_truck_factory_geofence() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_factory record; v_distance numeric;
begin
 select o.factory_latitude,o.factory_longitude,o.factory_geofence_radius_m into v_factory from public.organizations o where o.id=new.organization_id;
 if new.current_latitude is null or new.current_longitude is null or v_factory.factory_latitude is null or v_factory.factory_longitude is null then new.factory_distance_m:=null; new.factory_geofence_state:='unknown'; new.factory_geofence_checked_at:=now(); return new; end if;
 v_distance:=6371000*2*asin(sqrt(least(1,power(sin(radians((v_factory.factory_latitude-new.current_latitude)::float8/2)),2)+cos(radians(new.current_latitude::float8))*cos(radians(v_factory.factory_latitude::float8))*power(sin(radians((v_factory.factory_longitude-new.current_longitude)::float8/2)),2))));
 new.factory_distance_m:=round(v_distance,2);
 if new.location_source in ('phone_gps','hardware_gps') and (new.current_location_accuracy_m is null or new.current_location_accuracy_m>150) then new.factory_geofence_state:='unknown';
 else new.factory_geofence_state:=case when v_distance<=v_factory.factory_geofence_radius_m then 'inside' when v_distance<=v_factory.factory_geofence_radius_m+500 then 'nearby' else 'outside' end; end if;
 new.factory_geofence_checked_at:=now(); return new;
end; $$;
drop trigger if exists dispatch_truck_factory_proximity on public.dispatch_trucks;
create trigger dispatch_truck_factory_proximity before insert or update of current_latitude,current_longitude,organization_id,current_location_accuracy_m,location_source on public.dispatch_trucks for each row execute function public.supplyos_refresh_truck_factory_geofence();
revoke all on function public.supplyos_refresh_truck_factory_geofence() from public,anon,authenticated;
create or replace function public.set_dispatch_truck_location(p_truck_id uuid,p_latitude numeric,p_longitude numeric) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid(); v_org_id uuid; v_truck public.dispatch_trucks%rowtype; v_stop record; v_distance numeric; v_state text; v_previous text; v_new_count integer:=0;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 if p_latitude is null or p_longitude is null or p_latitude < -90 or p_latitude > 90 or p_longitude < -180 or p_longitude > 180 then raise exception 'Enter valid latitude (-90 to 90) and longitude (-180 to 180).'; end if;
 select t.* into v_truck from public.dispatch_trucks t where t.id=p_truck_id and exists(select 1 from public.memberships m where m.organization_id=t.organization_id and m.user_id=v_user_id) for update;
 if not found then raise exception 'Truck not found in this workspace.'; end if; v_org_id:=v_truck.organization_id;
 update public.dispatch_trucks set current_latitude=p_latitude,current_longitude=p_longitude,current_location_accuracy_m=null,location_source='manual',location_updated_at=now(),updated_at=now() where id=p_truck_id and organization_id=v_org_id;
 for v_stop in select l.id as load_id,l.geofence_radius_m,b.id as booking_id,b.latitude,b.longitude from public.dispatch_loads l join public.dispatch_load_bookings lb on lb.load_id=l.id join public.bookings b on b.id=lb.booking_id where l.organization_id=v_org_id and l.assigned_truck_id=p_truck_id and l.status='in_transit' and b.latitude is not null and b.longitude is not null loop
  v_distance:=6371000*2*asin(sqrt(least(1,power(sin(radians((v_stop.latitude-p_latitude)::float8/2)),2)+cos(radians(p_latitude::float8))*cos(radians(v_stop.latitude::float8))*power(sin(radians((v_stop.longitude-p_longitude)::float8/2)),2))));
  v_state:=case when v_distance<=v_stop.geofence_radius_m then 'inside' when v_distance<=v_stop.geofence_radius_m+500 then 'nearby' else 'outside' end;
  select s.state into v_previous from public.dispatch_geofence_states s where s.load_id=v_stop.load_id and s.booking_id=v_stop.booking_id for update;
  insert into public.dispatch_geofence_states(organization_id,load_id,booking_id,state,distance_m,radius_m,last_checked_at) values(v_org_id,v_stop.load_id,v_stop.booking_id,v_state,round(v_distance,2),v_stop.geofence_radius_m,now()) on conflict(load_id,booking_id) do update set state=excluded.state,distance_m=excluded.distance_m,radius_m=excluded.radius_m,last_checked_at=now();
  if v_previous is distinct from v_state then insert into public.dispatch_geofence_events(organization_id,load_id,booking_id,truck_id,previous_state,new_state,distance_m) values(v_org_id,v_stop.load_id,v_stop.booking_id,p_truck_id,v_previous,v_state,round(v_distance,2)); v_new_count:=v_new_count+1; end if;
 end loop;
 insert into public.dispatch_events(organization_id,actor_id,action,details) values(v_org_id,v_user_id,'truck_location_updated',jsonb_build_object('truck_id',p_truck_id,'latitude',p_latitude,'longitude',p_longitude,'geofence_transitions',v_new_count));
 return jsonb_build_object('geofence_transitions',v_new_count,'location_updated_at',now());
end; $$;
revoke all on function public.set_dispatch_truck_location(uuid,numeric,numeric) from public,anon;
grant execute on function public.set_dispatch_truck_location(uuid,numeric,numeric) to authenticated;
create or replace function public.record_dispatch_tracking_location(p_session_id uuid,p_latitude double precision,p_longitude double precision,p_accuracy_m double precision default null,p_recorded_at timestamptz default now()) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid:=auth.uid(); v_session public.dispatch_tracking_sessions%rowtype;
begin
 if v_user is null then raise exception 'Please sign in first.'; end if;
 if p_latitude is null or p_longitude is null or p_latitude < -90 or p_latitude > 90 or p_longitude < -180 or p_longitude > 180 then raise exception 'Invalid GPS coordinates.'; end if;
 if p_accuracy_m is not null and (p_accuracy_m<0 or p_accuracy_m>10000) then raise exception 'Invalid GPS accuracy.'; end if;
 if p_recorded_at is null or p_recorded_at>now()+interval '30 seconds' or p_recorded_at<now()-interval '5 minutes' then raise exception 'GPS fix is too old or has an invalid timestamp; wait for a fresh fix.'; end if;
 select * into v_session from public.dispatch_tracking_sessions s where s.id=p_session_id and s.driver_user_id=v_user and s.ended_at is null for update;
 if not found then raise exception 'Tracking session is no longer active for this driver.'; end if;
 if not exists(select 1 from public.dispatch_loads l where l.id=v_session.load_id and l.organization_id=v_session.organization_id and l.assigned_truck_id=v_session.truck_id and l.status='in_transit') then raise exception 'Load is no longer in transit with this truck. Tracking update rejected.'; end if;
 if not exists(select 1 from public.dispatch_truck_driver_assignments a where a.truck_id=v_session.truck_id and a.organization_id=v_session.organization_id and a.driver_user_id=v_user and a.active) or not exists(select 1 from public.memberships m where m.organization_id=v_session.organization_id and m.user_id=v_user and m.role='staff') then raise exception 'Driver assignment is no longer active. Tracking update rejected.'; end if;
 if p_accuracy_m is not null and p_accuracy_m<=150 then
  perform public.set_dispatch_truck_location(v_session.truck_id,p_latitude::numeric,p_longitude::numeric);
  update public.dispatch_trucks set current_location_accuracy_m=p_accuracy_m,location_source='phone_gps' where id=v_session.truck_id and organization_id=v_session.organization_id;
 else
  update public.dispatch_trucks set current_latitude=p_latitude,current_longitude=p_longitude,current_location_accuracy_m=p_accuracy_m,location_source='phone_gps',location_updated_at=now(),updated_at=now() where id=v_session.truck_id and organization_id=v_session.organization_id;
 end if;
 update public.dispatch_tracking_sessions set last_location_at=now() where id=v_session.id;
 return jsonb_build_object('accepted',true,'server_received_at',now(),'recorded_at',p_recorded_at,'truck_id',v_session.truck_id,'factory_geofence_state',(select t.factory_geofence_state from public.dispatch_trucks t where t.id=v_session.truck_id));
end; $$;
revoke all on function public.record_dispatch_tracking_location(uuid,double precision,double precision,double precision,timestamptz) from public,anon;
grant execute on function public.record_dispatch_tracking_location(uuid,double precision,double precision,double precision,timestamptz) to authenticated;
