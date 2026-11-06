-- Collection queue: persisted follow-up tasks tied to customers and (optionally) open invoices.
create table if not exists public.sales_recovery_tasks (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 customer_id uuid not null references public.customers(id) on delete restrict, invoice_id uuid references public.sales_invoices(id) on delete set null,
 task_no text not null default ('RCV-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10))),
 task_type text not null default 'call' check (task_type in ('call','email','visit','payment_promise','dispute','other')),
 priority text not null default 'medium' check (priority in ('low','medium','high','urgent')),
 status text not null default 'open' check (status in ('open','in_progress','resolved','cancelled')),
 summary text not null check (char_length(trim(summary)) between 3 and 180), notes text not null default '',
 due_date date not null default current_date, next_action_at date, outcome text not null default '',
 assigned_to uuid references auth.users(id) on delete set null, created_by uuid not null references auth.users(id),
 resolved_by uuid references auth.users(id), resolved_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(organization_id,task_no)
);
create index if not exists sales_recovery_tasks_org_status_idx on public.sales_recovery_tasks(organization_id,status,priority,due_date);
create index if not exists sales_recovery_tasks_customer_idx on public.sales_recovery_tasks(customer_id,created_at desc);
alter table public.sales_recovery_tasks enable row level security;
revoke all on public.sales_recovery_tasks from anon,authenticated;
grant select on public.sales_recovery_tasks to authenticated;
drop policy if exists sales_recovery_tasks_read_org on public.sales_recovery_tasks;
create policy sales_recovery_tasks_read_org on public.sales_recovery_tasks for select to authenticated using(organization_id in(select m.organization_id from public.memberships m where m.user_id=(select auth.uid())));

create or replace function public.create_sales_recovery_task(p_customer_id uuid,p_invoice_id uuid,p_due_date date,p_priority text,p_task_type text,p_summary text,p_notes text default '')
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_task_id uuid;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
 if not exists(select 1 from public.memberships where organization_id=v_org_id and user_id=v_user_id and role in ('owner','admin','manager','accountant','staff')) then raise exception 'You do not have sales recovery permission.'; end if;
 if not exists(select 1 from public.customers c where c.id=p_customer_id and c.organization_id=v_org_id) then raise exception 'Customer not found in this workspace.'; end if;
 if p_invoice_id is not null and not exists(select 1 from public.sales_invoices i where i.id=p_invoice_id and i.organization_id=v_org_id and i.customer_id=p_customer_id and i.status<>'void' and i.balance_due>0) then raise exception 'Choose an open invoice for the selected customer.'; end if;
 if p_priority not in ('low','medium','high','urgent') then raise exception 'Choose a valid priority.'; end if;
 if p_task_type not in ('call','email','visit','payment_promise','dispute','other') then raise exception 'Choose a valid follow-up type.'; end if;
 if char_length(trim(coalesce(p_summary,'')))<3 or char_length(trim(p_summary))>180 then raise exception 'Enter a short follow-up summary (3–180 characters).'; end if;
 insert into public.sales_recovery_tasks(organization_id,customer_id,invoice_id,due_date,priority,task_type,summary,notes,assigned_to,created_by)
 values(v_org_id,p_customer_id,p_invoice_id,coalesce(p_due_date,current_date),p_priority,p_task_type,trim(p_summary),left(trim(coalesce(p_notes,'')),2000),v_user_id,v_user_id) returning id into v_task_id;
 return v_task_id;
end; $$;
create or replace function public.update_sales_recovery_task(p_task_id uuid,p_status text,p_outcome text,p_next_action_at date default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
 if p_status not in ('open','in_progress','resolved','cancelled') then raise exception 'Choose a valid task status.'; end if;
 if p_status='resolved' and char_length(trim(coalesce(p_outcome,'')))<3 then raise exception 'Describe the recovery outcome before closing the task.'; end if;
 update public.sales_recovery_tasks set status=p_status,outcome=left(trim(coalesce(p_outcome,'')),2000),next_action_at=p_next_action_at,
  resolved_by=case when p_status='resolved' then v_user_id else null end,resolved_at=case when p_status='resolved' then now() else null end,updated_at=now()
 where id=p_task_id and organization_id=v_org_id and status in ('open','in_progress');
 if not found then raise exception 'Open recovery task not found in this workspace.'; end if;
end; $$;
revoke all on function public.create_sales_recovery_task(uuid,uuid,date,text,text,text,text) from public,anon;
revoke all on function public.update_sales_recovery_task(uuid,text,text,date) from public,anon;
grant execute on function public.create_sales_recovery_task(uuid,uuid,date,text,text,text,text) to authenticated;
grant execute on function public.update_sales_recovery_task(uuid,text,text,date) to authenticated;
