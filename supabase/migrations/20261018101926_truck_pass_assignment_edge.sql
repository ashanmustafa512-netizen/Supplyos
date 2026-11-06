-- If a ready load had no truck at the time its status changed, assigning a truck later must still create/reset a pass.
create or replace function public.supplyos_reset_truck_pass_on_reassignment()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_snapshot jsonb; v_pass_id uuid;
begin
  if new.assigned_truck_id is distinct from old.assigned_truck_id then
    if new.assigned_truck_id is null then
      update public.dispatch_truck_passes set status='hold',updated_at=now() where load_id=new.id and status<>'hold';
    elsif exists(select 1 from public.dispatch_truck_passes p where p.load_id=new.id) then
      v_snapshot:=public.supplyos_truck_pass_snapshot(new.id);
      update public.dispatch_truck_passes set truck_id=new.assigned_truck_id,status='inspection_pending',
        checklist='{"tyres_checked":false,"brakes_checked":false,"lights_checked":false,"mirrors_checked":false,"horn_reverse_checked":false,"fire_extinguisher_checked":false,"documents_checked":false,"cargo_secured":false}'::jsonb,
        inspection_snapshot=coalesce(v_snapshot,'{}'::jsonb),inspection_notes='',checked_by=null,checked_at=null,updated_at=now() where load_id=new.id;
    elsif new.status='ready' then
      v_snapshot:=public.supplyos_truck_pass_snapshot(new.id);
      insert into public.dispatch_truck_passes(organization_id,load_id,truck_id,inspection_snapshot,issued_by)
      values(new.organization_id,new.id,new.assigned_truck_id,coalesce(v_snapshot,'{}'::jsonb),auth.uid())
      on conflict(load_id) do nothing returning id into v_pass_id;
      if v_pass_id is not null then
        insert into public.dispatch_events(organization_id,load_id,actor_id,action,details)
        values(new.organization_id,new.id,auth.uid(),'truck_pass_generated_after_truck_assignment',jsonb_build_object('truck_pass_id',v_pass_id,'truck_id',new.assigned_truck_id));
      end if;
    end if;
  end if;
  return new;
end; $$;
revoke all on function public.supplyos_reset_truck_pass_on_reassignment() from public,anon,authenticated;
