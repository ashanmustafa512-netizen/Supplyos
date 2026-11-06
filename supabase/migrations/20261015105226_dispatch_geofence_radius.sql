create or replace function public.set_dispatch_geofence_radius(p_load_id uuid,p_radius_m integer)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid(); v_org_id uuid;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select m.organization_id into v_org_id from public.memberships m where m.user_id=v_user_id limit 1;
 if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
 if p_radius_m is null or p_radius_m<25 or p_radius_m>10000 then raise exception 'Geofence radius must be between 25 and 10,000 metres.'; end if;
 update public.dispatch_loads set geofence_radius_m=p_radius_m,updated_at=now() where id=p_load_id and organization_id=v_org_id and status not in ('delivered','cancelled');
 if not found then raise exception 'Open load not found in this workspace.'; end if;
 insert into public.dispatch_events(organization_id,load_id,actor_id,action,details) values(v_org_id,p_load_id,v_user_id,'geofence_radius_updated',jsonb_build_object('radius_m',p_radius_m));
end; $$;
revoke all on function public.set_dispatch_geofence_radius(uuid,integer) from public,anon;
grant execute on function public.set_dispatch_geofence_radius(uuid,integer) to authenticated;
