-- Team accounts provisioned by an Owner belong to that owner's existing workspace.
-- Public self-sign-up still creates an Owner workspace; managed accounts do not.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
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

  -- The authenticated Edge Function sets this marker only while creating a
  -- manager/employee through the Owner's team-access screen. It adds the real
  -- organization membership after the Auth user is created. A public client
  -- can spoof the marker and get no workspace, but cannot assign themselves
  -- any membership or privileged role.
  if coalesce(new.raw_user_meta_data ->> 'supplyos_managed_account', 'false') = 'true' then
    return new;
  end if;

  insert into public.organizations (name, owner_id)
  values (
    coalesce(v_company_name, split_part(coalesce(new.email, 'Factory'), '@', 1) || ' Factory'),
    new.id
  )
  returning id into v_org_id;

  insert into public.memberships (organization_id, user_id, role)
  values (v_org_id, new.id, 'owner');

  return new;
end;
$function$;
