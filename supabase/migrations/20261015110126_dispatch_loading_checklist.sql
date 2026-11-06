alter table public.dispatch_loads add column if not exists loading_checklist jsonb not null default '{"quantities_verified":false,"packages_checked":false,"cargo_secured":false,"documents_ready":false}'::jsonb;
create or replace function public.finish_dispatch_loading(p_load_id uuid,p_checklist jsonb,p_loading_notes text default '')
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid(); v_org_id uuid; v_load public.dispatch_loads%rowtype;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select m.organization_id into v_org_id from public.memberships m where m.user_id=v_user_id limit 1;
 if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
 if p_checklist is null or coalesce(p_checklist->>'quantities_verified','false')<>'true' or coalesce(p_checklist->>'packages_checked','false')<>'true' or coalesce(p_checklist->>'cargo_secured','false')<>'true' or coalesce(p_checklist->>'documents_ready','false')<>'true' then raise exception 'Complete all four loading checks before making a load ready.'; end if;
 select * into v_load from public.dispatch_loads where id=p_load_id and organization_id=v_org_id for update;
 if not found then raise exception 'Load not found in this workspace.'; end if;
 if v_load.status<>'planned' or v_load.loading_status<>'loading' then raise exception 'Start the loading process before completing its checklist.'; end if;
 if v_load.assigned_truck_id is null then raise exception 'Assign a truck before completing loading.'; end if;
 if not exists(select 1 from public.dispatch_trucks t where t.id=v_load.assigned_truck_id and t.organization_id=v_org_id and t.status='available') then raise exception 'Assigned truck is not available. Review the truck assignment.'; end if;
 if not exists(select 1 from public.dispatch_load_bookings where load_id=p_load_id) then raise exception 'This load has no bookings.'; end if;
 if exists(select 1 from public.dispatch_load_bookings lb join public.bookings b on b.id=lb.booking_id where lb.load_id=p_load_id and b.status<>'approved') then raise exception 'Every booking must remain approved before the vehicle departs.'; end if;
 update public.dispatch_loads set loading_checklist=p_checklist,loading_notes=left(trim(coalesce(p_loading_notes,'')),2000),updated_at=now() where id=p_load_id and organization_id=v_org_id;
 perform public.dispatch_load_action(p_load_id,'finish_loading');
end; $$;
revoke all on function public.finish_dispatch_loading(uuid,jsonb,text) from public,anon;
grant execute on function public.finish_dispatch_loading(uuid,jsonb,text) to authenticated;
