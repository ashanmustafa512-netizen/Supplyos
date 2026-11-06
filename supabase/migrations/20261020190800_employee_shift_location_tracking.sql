create table if not exists public.employee_location_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  employee_name text not null,
  consent_version text not null,
  consent_at timestamptz not null default now(),
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  last_location_at timestamptz,
  current_latitude double precision,
  current_longitude double precision,
  current_location_accuracy_m double precision,
  location_source text not null default 'phone_gps' check (location_source in ('phone_gps')),
  factory_distance_m double precision,
  factory_geofence_state text not null default 'unknown' check (factory_geofence_state in ('inside','nearby','outside','unknown')),
  factory_geofence_checked_at timestamptz,
  stop_reason text,
  created_at timestamptz not null default now(),
  constraint employee_location_latitude_valid check (current_latitude is null or current_latitude between -90 and 90),
  constraint employee_location_longitude_valid check (current_longitude is null or current_longitude between -180 and 180),
  constraint employee_location_accuracy_valid check (current_location_accuracy_m is null or current_location_accuracy_m between 0 and 10000)
);
create index if not exists employee_location_sessions_org_active_idx on public.employee_location_sessions(organization_id, started_at desc) where ended_at is null;
create index if not exists employee_location_sessions_user_active_idx on public.employee_location_sessions(user_id, started_at desc) where ended_at is null;
create unique index if not exists employee_location_one_active_per_user on public.employee_location_sessions(user_id) where ended_at is null;

alter table public.employee_location_sessions enable row level security;
revoke all on public.employee_location_sessions from anon, public;
grant select on public.employee_location_sessions to authenticated;
drop policy if exists employee_location_sessions_read_authorized on public.employee_location_sessions;
create policy employee_location_sessions_read_authorized on public.employee_location_sessions for select to authenticated using (
  user_id = (select auth.uid()) or exists (
    select 1 from public.memberships m where m.organization_id = employee_location_sessions.organization_id
    and m.user_id = (select auth.uid()) and m.role in ('owner','admin','manager','dispatcher')
  )
);

create or replace function public.start_employee_location_shift(p_consent_version text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid := auth.uid(); v_org uuid; v_name text; v_session uuid;
begin
  if v_user is null then raise exception 'Please sign in before starting location sharing.'; end if;
  if p_consent_version is null or length(trim(p_consent_version)) < 3 or length(p_consent_version) > 80 then raise exception 'Explicit employee location consent is required.'; end if;
  select m.organization_id into v_org from public.memberships m where m.user_id=v_user
    order by case when m.role in ('staff','dispatcher','manager','admin','owner') then 0 else 1 end limit 1;
  if v_org is null then raise exception 'Your account is not assigned to a factory workspace.'; end if;
  if exists(select 1 from public.employee_location_sessions s where s.user_id=v_user and s.ended_at is null) then raise exception 'An employee location session is already active on this account.'; end if;
  if exists(select 1 from public.dispatch_tracking_sessions s where s.driver_user_id=v_user and s.ended_at is null) then raise exception 'End the active delivery trip before starting an employee shift location session.'; end if;
  select coalesce(nullif(trim(p.full_name),''),'Employee '||left(v_user::text,8)) into v_name from public.profiles p where p.id=v_user;
  if v_name is null then v_name := 'Employee '||left(v_user::text,8); end if;
  insert into public.employee_location_sessions(organization_id,user_id,employee_name,consent_version) values(v_org,v_user,v_name,p_consent_version) returning id into v_session;
  return jsonb_build_object('session_id',v_session,'organization_id',v_org,'employee_name',v_name,'started_at',now(),'consent_version',p_consent_version);
end; $$;

create or replace function public.record_employee_location(p_session_id uuid,p_latitude double precision,p_longitude double precision,p_accuracy_m double precision default null,p_recorded_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid:=auth.uid(); v_session public.employee_location_sessions%rowtype; v_factory record; v_distance double precision; v_state text;
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
  update public.employee_location_sessions set current_latitude=p_latitude,current_longitude=p_longitude,current_location_accuracy_m=p_accuracy_m,location_source='phone_gps',factory_distance_m=v_distance,factory_geofence_state=v_state,factory_geofence_checked_at=now(),last_location_at=now() where id=v_session.id;
  return jsonb_build_object('accepted',true,'server_received_at',now(),'recorded_at',p_recorded_at,'factory_distance_m',v_distance,'factory_geofence_state',v_state);
end; $$;

create or replace function public.stop_employee_location_shift(p_session_id uuid,p_reason text default 'employee_stopped')
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid:=auth.uid(); v_session public.employee_location_sessions%rowtype;
begin
  if v_user is null then raise exception 'Please sign in first.'; end if;
  select * into v_session from public.employee_location_sessions s where s.id=p_session_id and s.user_id=v_user and s.ended_at is null for update;
  if not found then raise exception 'No active employee location session belongs to this account.'; end if;
  update public.employee_location_sessions set ended_at=now(),stop_reason=left(coalesce(p_reason,'employee_stopped'),80) where id=v_session.id;
  return jsonb_build_object('stopped',true,'session_id',v_session.id,'ended_at',now());
end; $$;

create or replace function public.admin_stop_employee_location_shift(p_session_id uuid,p_reason text default 'manager_stopped')
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user uuid:=auth.uid(); v_session public.employee_location_sessions%rowtype;
begin
  if v_user is null then raise exception 'Please sign in first.'; end if;
  select * into v_session from public.employee_location_sessions s where s.id=p_session_id and s.ended_at is null and exists(
    select 1 from public.memberships m where m.organization_id=s.organization_id and m.user_id=v_user and m.role in ('owner','admin','manager','dispatcher')
  ) for update;
  if not found then raise exception 'Active employee session not found or you do not have permission.'; end if;
  update public.employee_location_sessions set ended_at=now(),stop_reason=left(coalesce(p_reason,'manager_stopped'),80) where id=v_session.id;
  return jsonb_build_object('stopped',true,'session_id',v_session.id,'ended_at',now());
end; $$;
revoke all on function public.start_employee_location_shift(text) from public,anon;
revoke all on function public.record_employee_location(uuid,double precision,double precision,double precision,timestamptz) from public,anon;
revoke all on function public.stop_employee_location_shift(uuid,text) from public,anon;
revoke all on function public.admin_stop_employee_location_shift(uuid,text) from public,anon;
grant execute on function public.start_employee_location_shift(text) to authenticated;
grant execute on function public.record_employee_location(uuid,double precision,double precision,double precision,timestamptz) to authenticated;
grant execute on function public.stop_employee_location_shift(uuid,text) to authenticated;
grant execute on function public.admin_stop_employee_location_shift(uuid,text) to authenticated;
do $$ begin if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='employee_location_sessions') then alter publication supabase_realtime add table public.employee_location_sessions; end if; end $$;
