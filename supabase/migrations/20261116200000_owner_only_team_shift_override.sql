-- Only owners/admins can close another team member's shift from the live map.
do $owner_stop$
declare
  v_oid oid;
  v_definition text;
  v_original text;
begin
  select p.oid into v_oid
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'admin_stop_employee_location_shift'
  limit 1;

  if v_oid is null then
    raise exception 'admin_stop_employee_location_shift was not found.';
  end if;

  v_definition := pg_get_functiondef(v_oid);
  v_original := v_definition;
  v_definition := replace(
    v_definition,
    'role in (''owner'',''admin'',''manager'',''dispatcher'')',
    'role in (''owner'',''admin'')'
  );

  if v_definition = v_original then
    raise exception 'Could not restrict admin_stop_employee_location_shift to owner/admin.';
  end if;

  execute v_definition;
end;
$owner_stop$;
