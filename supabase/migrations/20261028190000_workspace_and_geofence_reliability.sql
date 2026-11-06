-- SupplyOS reliability patch: backfill a private workspace for older sign-ins and
-- make factory geofence writes role-safe, validated, and verifiable.
-- Apply only after the existing SupplyOS baseline and dispatch/geofence migrations.

create or replace function public.ensure_my_workspace()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_claims jsonb := coalesce(auth.jwt()::jsonb, '{}'::jsonb);
  v_org_id uuid;
  v_role text;
  v_email text;
  v_company_name text;
  v_full_name text;
begin
  if v_user_id is null then
    raise exception 'Please sign in before creating a workspace.';
  end if;

  -- Serialize simultaneous page requests from the same account to avoid duplicate workspaces.
  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text, 0));

  select m.organization_id, m.role
    into v_org_id, v_role
    from public.memberships m
    where m.user_id = v_user_id
    order by m.created_at asc
    limit 1;

  if v_org_id is not null then
    return jsonb_build_object('organization_id', v_org_id, 'role', v_role, 'created', false);
  end if;

  v_email := coalesce(nullif(trim(v_claims ->> 'email'), ''), 'factory');
  v_company_name := nullif(trim(coalesce(v_claims -> 'user_metadata' ->> 'company_name', '')), '');
  v_full_name := nullif(trim(coalesce(v_claims -> 'user_metadata' ->> 'full_name', '')), '');
  if v_company_name is null then
    v_company_name := split_part(v_email, '@', 1) || ' Factory';
  end if;

  -- Recover an orphaned company row before creating a fresh one.
  select o.id into v_org_id
    from public.organizations o
    where o.owner_id = v_user_id
    order by o.created_at asc
    limit 1;
  if v_org_id is not null then
    insert into public.profiles (id, full_name)
    values (v_user_id, coalesce(v_full_name, ''))
    on conflict (id) do nothing;
    insert into public.memberships (organization_id, user_id, role)
    values (v_org_id, v_user_id, 'owner')
    on conflict (organization_id, user_id) do nothing;
    return jsonb_build_object('organization_id', v_org_id, 'role', 'owner', 'created', false, 'recovered', true);
  end if;

  insert into public.profiles (id, full_name)
  values (v_user_id, coalesce(v_full_name, ''))
  on conflict (id) do nothing;

  insert into public.organizations (name, owner_id)
  values (left(v_company_name, 120), v_user_id)
  returning id into v_org_id;

  insert into public.memberships (organization_id, user_id, role)
  values (v_org_id, v_user_id, 'owner');

  return jsonb_build_object('organization_id', v_org_id, 'role', 'owner', 'created', true);
end;
$$;

revoke all on function public.ensure_my_workspace() from public, anon;
grant execute on function public.ensure_my_workspace() to authenticated;

create or replace function public.set_dispatch_factory_geofence(
  p_latitude numeric,
  p_longitude numeric,
  p_address text,
  p_radius_m integer default 250
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_org_id uuid;
  v_role text;
  v_org public.organizations%rowtype;
begin
  if v_user_id is null then
    raise exception 'Please sign in first.';
  end if;

  select m.organization_id, lower(btrim(m.role))
    into v_org_id, v_role
    from public.memberships m
    where m.user_id = v_user_id
    order by m.created_at asc
    limit 1;

  if v_org_id is null then
    raise exception 'No factory workspace is linked to this account. Reopen SupplyOS after applying the workspace reliability migration.';
  end if;
  if coalesce(v_role, '') not in ('owner', 'admin', 'manager') then
    raise exception 'Only a factory owner, admin or manager can change the factory geofence.';
  end if;
  if p_latitude is null or p_longitude is null
     or p_latitude < -90 or p_latitude > 90
     or p_longitude < -180 or p_longitude > 180 then
    raise exception 'Set valid decimal coordinates (latitude -90 to 90 and longitude -180 to 180).';
  end if;
  if p_radius_m is null or p_radius_m < 25 or p_radius_m > 10000 then
    raise exception 'Factory geofence radius must be from 25 to 10,000 metres.';
  end if;

  update public.organizations
     set factory_latitude = p_latitude,
         factory_longitude = p_longitude,
         factory_address = left(trim(coalesce(p_address, '')), 300),
         factory_geofence_radius_m = p_radius_m
   where id = v_org_id
   returning * into v_org;

  if not found then
    raise exception 'The factory workspace could not be updated.';
  end if;

  -- Force the database trigger to recalculate each vehicle's distance/state against the new factory point.
  update public.dispatch_trucks t
     set current_latitude = t.current_latitude,
         current_longitude = t.current_longitude
   where t.organization_id = v_org_id;

  insert into public.dispatch_events (organization_id, actor_id, action, details)
  values (
    v_org_id,
    v_user_id,
    'factory_geofence_updated',
    jsonb_build_object(
      'latitude', v_org.factory_latitude,
      'longitude', v_org.factory_longitude,
      'radius_m', v_org.factory_geofence_radius_m,
      'address', v_org.factory_address,
      'saved_at', now()
    )
  );

  return jsonb_build_object(
    'organization_id', v_org.id,
    'factory_latitude', v_org.factory_latitude,
    'factory_longitude', v_org.factory_longitude,
    'factory_address', v_org.factory_address,
    'factory_geofence_radius_m', v_org.factory_geofence_radius_m
  );
end;
$$;

revoke all on function public.set_dispatch_factory_geofence(numeric, numeric, text, integer) from public, anon;
grant execute on function public.set_dispatch_factory_geofence(numeric, numeric, text, integer) to authenticated;

-- Supporting indexes for the main live-position and current-shift reads.
create index if not exists dispatch_trucks_org_position_updated_idx
  on public.dispatch_trucks (organization_id, location_updated_at desc)
  where current_latitude is not null and current_longitude is not null;

create index if not exists dispatch_geofence_states_org_checked_idx
  on public.dispatch_geofence_states (organization_id, last_checked_at desc);
