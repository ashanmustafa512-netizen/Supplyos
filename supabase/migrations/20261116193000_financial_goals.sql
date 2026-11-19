-- Owner-managed monthly financial targets used by the accounting workspace.
alter table public.organizations
  add column if not exists monthly_revenue_goal numeric(14,2) not null default 0,
  add column if not exists monthly_expense_budget numeric(14,2) not null default 0;

alter table public.organizations
  drop constraint if exists organizations_monthly_revenue_goal_nonnegative,
  drop constraint if exists organizations_monthly_expense_budget_nonnegative;

alter table public.organizations
  add constraint organizations_monthly_revenue_goal_nonnegative check (monthly_revenue_goal >= 0),
  add constraint organizations_monthly_expense_budget_nonnegative check (monthly_expense_budget >= 0);

create or replace function public.set_financial_goals(
  p_monthly_revenue_goal numeric,
  p_monthly_expense_budget numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user uuid := auth.uid();
  v_org uuid;
begin
  if v_user is null then raise exception 'Please sign in first.'; end if;
  if p_monthly_revenue_goal is null or p_monthly_revenue_goal < 0
     or p_monthly_expense_budget is null or p_monthly_expense_budget < 0 then
    raise exception 'Monthly targets must be zero or greater.';
  end if;

  v_org := public.supplyos_current_organization_id();
  if not exists (
    select 1 from public.memberships m
    where m.organization_id = v_org and m.user_id = v_user
      and m.role in ('owner', 'admin')
  ) then
    raise exception 'Only the owner or admin can change company financial goals.';
  end if;

  update public.organizations
  set monthly_revenue_goal = round(p_monthly_revenue_goal, 2),
      monthly_expense_budget = round(p_monthly_expense_budget, 2)
  where id = v_org;

  return jsonb_build_object(
    'monthly_revenue_goal', round(p_monthly_revenue_goal, 2),
    'monthly_expense_budget', round(p_monthly_expense_budget, 2)
  );
end;
$function$;

revoke all on function public.set_financial_goals(numeric, numeric) from public, anon;
grant execute on function public.set_financial_goals(numeric, numeric) to authenticated;
