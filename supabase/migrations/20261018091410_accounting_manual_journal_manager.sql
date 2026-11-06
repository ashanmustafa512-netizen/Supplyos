-- Restrict manual journal posting to roles authorized for financial administration.
create or replace function public.create_manual_journal(p_date date,p_description text,p_lines jsonb)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_debit numeric;v_credit numeric;v_je uuid;v_count integer;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 if not exists(select 1 from public.memberships where organization_id=v_org_id and user_id=v_user_id and role in ('owner','admin','manager','accountant')) then raise exception 'Only authorized finance roles can post manual journals.'; end if;
 if nullif(trim(p_description),'') is null or jsonb_typeof(p_lines)<>'array' then raise exception 'Journal description and lines are required.'; end if;
 select count(*),coalesce(sum((x->>'debit')::numeric),0),coalesce(sum((x->>'credit')::numeric),0) into v_count,v_debit,v_credit from jsonb_array_elements(p_lines) x;
 if v_count<2 or v_count>30 then raise exception 'A journal must have 2 to 30 lines.'; end if;
 if v_debit<=0 or round(v_debit,2)<>round(v_credit,2) then raise exception 'Journal debits and credits must be equal and greater than zero.'; end if;
 if exists(select 1 from jsonb_array_elements(p_lines) x where coalesce((x->>'debit')::numeric,0)<0 or coalesce((x->>'credit')::numeric,0)<0 or ((coalesce((x->>'debit')::numeric,0)>0)=(coalesce((x->>'credit')::numeric,0)>0))) then raise exception 'Each journal line must have either a debit or a credit, never both.'; end if;
 if exists(select 1 from jsonb_array_elements(p_lines) x where not exists(select 1 from public.finance_accounts a where a.id=(x->>'account_id')::uuid and a.organization_id=v_org_id and a.is_active)) then raise exception 'Every line must use an active account from this workspace.'; end if;
 insert into public.accounting_journal_entries(organization_id,entry_date,source_type,description,status,debit_total,credit_total,created_by,posted_by,posted_at)
 values(v_org_id,coalesce(p_date,current_date),'manual',trim(p_description),'posted',round(v_debit,2),round(v_credit,2),v_user_id,v_user_id,now()) returning id into v_je;
 insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit)
 select v_org_id,v_je,(x->>'account_id')::uuid,left(trim(coalesce(x->>'description','')),250),round(coalesce((x->>'debit')::numeric,0),2),round(coalesce((x->>'credit')::numeric,0),2) from jsonb_array_elements(p_lines) x;
 return v_je;
end; $$;
revoke all on function public.create_manual_journal(date,text,jsonb) from public,anon;
grant execute on function public.create_manual_journal(date,text,jsonb) to authenticated;
