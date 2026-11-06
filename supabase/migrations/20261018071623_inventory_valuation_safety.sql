-- Keep stock quantity changes and inventory valuation changes auditable and balanced.
create or replace function public.save_stock_product(
 p_product_id uuid,p_sku text,p_name text,p_unit text,p_category text,p_barcode text,
 p_unit_cost numeric,p_unit_price numeric,p_stock_on_hand numeric,p_unit_weight_kg numeric,
 p_raw_material_cost numeric,p_direct_labor_cost numeric,p_production_overhead numeric,p_reorder_level numeric,
 p_is_active boolean,p_default_supplier_id uuid
) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_product_id uuid;v_existing public.products%rowtype;v_je uuid;v_inventory uuid;v_offset uuid;v_production_cost numeric(14,2);v_revaluation numeric(14,2);v_amount numeric(14,2);
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select m.organization_id into v_org_id from public.memberships m where m.user_id=v_user_id limit 1;
 if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
 if not exists(select 1 from public.memberships m where m.organization_id=v_org_id and m.user_id=v_user_id and m.role in ('owner','admin','manager','staff')) then raise exception 'You do not have inventory editing permission.'; end if;
 if nullif(trim(p_sku),'') is null or nullif(trim(p_name),'') is null then raise exception 'SKU and product name are required.'; end if;
 if length(trim(p_sku))>40 or length(trim(p_name))>160 then raise exception 'SKU or product name is too long.'; end if;
 if least(coalesce(p_unit_cost,-1),coalesce(p_unit_price,-1),coalesce(p_stock_on_hand,-1),coalesce(p_unit_weight_kg,-1),coalesce(p_raw_material_cost,-1),coalesce(p_direct_labor_cost,-1),coalesce(p_production_overhead,-1),coalesce(p_reorder_level,-1))<0 then raise exception 'Cost, price, stock, weight, production components, and reorder level must be non-negative.'; end if;
 if p_default_supplier_id is not null and not exists(select 1 from public.suppliers s where s.id=p_default_supplier_id and s.organization_id=v_org_id and s.is_active) then raise exception 'Choose an active supplier from this workspace.'; end if;
 v_production_cost:=round(coalesce(p_raw_material_cost,0)+coalesce(p_direct_labor_cost,0)+coalesce(p_production_overhead,0),2);
 if p_product_id is null then
  insert into public.products(organization_id,sku,name,unit,unit_cost,unit_price,stock_on_hand,unit_weight_kg,is_active,category,barcode,raw_material_cost,direct_labor_cost,production_overhead,production_cost,reorder_level,default_supplier_id)
  values(v_org_id,upper(trim(p_sku)),trim(p_name),coalesce(nullif(trim(p_unit),''),'unit'),p_unit_cost,p_unit_price,p_stock_on_hand,p_unit_weight_kg,coalesce(p_is_active,true),coalesce(nullif(trim(p_category),''),'General'),trim(coalesce(p_barcode,'')),p_raw_material_cost,p_direct_labor_cost,p_production_overhead,v_production_cost,p_reorder_level,p_default_supplier_id) returning id into v_product_id;
  v_amount:=round(p_stock_on_hand*p_unit_cost,2);
  if v_amount>0 then
   insert into public.accounting_journal_entries(organization_id,entry_date,source_type,source_id,description,status,debit_total,credit_total,created_by,posted_by,posted_at)
   values(v_org_id,current_date,'stock_opening',v_product_id,'Opening inventory - '||trim(p_name),'posted',v_amount,v_amount,v_user_id,v_user_id,now()) returning id into v_je;
   select id into v_inventory from public.finance_accounts where organization_id=v_org_id and code='1200';
   select id into v_offset from public.finance_accounts where organization_id=v_org_id and code='3000';
   insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit)
   values(v_org_id,v_je,v_inventory,'Opening stock: '||trim(p_name),v_amount,0),(v_org_id,v_je,v_offset,'Opening stock offset: '||trim(p_name),0,v_amount);
  end if;
 else
  select * into v_existing from public.products p where p.id=p_product_id and p.organization_id=v_org_id for update;
  if not found then raise exception 'Product not found in this workspace.'; end if;
  if p_stock_on_hand<>v_existing.stock_on_hand then raise exception 'Use Stock adjustment to change on-hand quantity. This keeps the stock ledger and accounting aligned.'; end if;
  if p_stock_on_hand<v_existing.stock_reserved then raise exception 'On-hand stock cannot be less than already reserved units.'; end if;
  v_revaluation:=round(v_existing.stock_on_hand*(p_unit_cost-v_existing.unit_cost),2);
  update public.products set sku=upper(trim(p_sku)),name=trim(p_name),unit=coalesce(nullif(trim(p_unit),''),'unit'),unit_cost=p_unit_cost,unit_price=p_unit_price,unit_weight_kg=p_unit_weight_kg,is_active=coalesce(p_is_active,true),category=coalesce(nullif(trim(p_category),''),'General'),barcode=trim(coalesce(p_barcode,'')),raw_material_cost=p_raw_material_cost,direct_labor_cost=p_direct_labor_cost,production_overhead=p_production_overhead,production_cost=v_production_cost,reorder_level=p_reorder_level,default_supplier_id=p_default_supplier_id
  where id=p_product_id and organization_id=v_org_id returning id into v_product_id;
  if v_revaluation<>0 then
   v_amount:=abs(v_revaluation);select id into v_inventory from public.finance_accounts where organization_id=v_org_id and code='1200';
   if v_revaluation>0 then select id into v_offset from public.finance_accounts where organization_id=v_org_id and code='4200'; else select id into v_offset from public.finance_accounts where organization_id=v_org_id and code='6600'; end if;
   insert into public.accounting_journal_entries(organization_id,entry_date,source_type,source_id,description,status,debit_total,credit_total,created_by,posted_by,posted_at)
   values(v_org_id,current_date,'inventory_revaluation',v_product_id,'Inventory cost revaluation - '||trim(p_name),'posted',v_amount,v_amount,v_user_id,v_user_id,now()) returning id into v_je;
   if v_revaluation>0 then
    insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit)
    values(v_org_id,v_je,v_inventory,'Inventory valuation increase: '||trim(p_name),v_amount,0),(v_org_id,v_je,v_offset,'Inventory valuation gain',0,v_amount);
   else
    insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit)
    values(v_org_id,v_je,v_offset,'Inventory valuation write-down',v_amount,0),(v_org_id,v_je,v_inventory,'Inventory valuation decrease: '||trim(p_name),0,v_amount);
   end if;
   insert into public.stock_movements(organization_id,product_id,warehouse_id,movement_type,quantity_delta,reserved_delta,stock_after,reserved_after,unit_cost,reference_type,reference_code,notes,created_by)
   select v_org_id,v_product_id,w.id,'revaluation',0,0,v_existing.stock_on_hand,v_existing.stock_reserved,p_unit_cost,'journal',v_je::text,'Carrying-value change from product cost edit',v_user_id from public.warehouses w where w.organization_id=v_org_id and w.is_default=true limit 1;
  end if;
 end if;
 return v_product_id;
exception when unique_violation then raise exception 'That SKU already exists in this workspace.'; end; $$;

create or replace function public.adjust_stock_balance(p_product_id uuid,p_quantity_delta numeric,p_unit_cost numeric default null,p_warehouse_id uuid default null,p_reason text default 'adjustment',p_notes text default '')
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_product public.products%rowtype;v_after numeric;v_cost numeric;v_asset uuid;v_offset uuid;v_je uuid;v_value numeric;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 select * into v_product from public.products where id=p_product_id and organization_id=v_org_id for update;
 if not found then raise exception 'Product not found in this workspace.'; end if;
 if p_quantity_delta is null or p_quantity_delta=0 then raise exception 'Adjustment quantity cannot be zero.'; end if;
 if p_unit_cost is not null and p_unit_cost<0 then raise exception 'Unit cost cannot be negative.'; end if;
 if p_unit_cost is not null and p_unit_cost<>v_product.unit_cost and v_product.stock_on_hand>0 then raise exception 'Change the product unit cost in the product editor. The editor posts the required inventory revaluation.'; end if;
 if p_warehouse_id is not null and not exists(select 1 from public.warehouses where id=p_warehouse_id and organization_id=v_org_id and is_active) then raise exception 'Choose an active warehouse.'; end if;
 v_after:=v_product.stock_on_hand+p_quantity_delta;
 if v_after<v_product.stock_reserved then raise exception 'The adjustment would place stock below reserved quantities.'; end if;
 v_cost:=coalesce(p_unit_cost,v_product.unit_cost);v_value:=round(abs(p_quantity_delta)*v_cost,2);
 if p_warehouse_id is not null then perform set_config('supplyos.warehouse_id',p_warehouse_id::text,true); end if;
 update public.products set stock_on_hand=v_after,unit_cost=v_cost where id=p_product_id and organization_id=v_org_id;
 select id into v_asset from public.finance_accounts where organization_id=v_org_id and code='1200';
 if p_quantity_delta>0 then v_offset:=(select id from public.finance_accounts where organization_id=v_org_id and code='4200'); else v_offset:=(select id from public.finance_accounts where organization_id=v_org_id and code='6600'); end if;
 insert into public.accounting_journal_entries(organization_id,entry_date,source_type,source_id,description,status,debit_total,credit_total,created_by,posted_by,posted_at)
 values(v_org_id,current_date,'stock_adjustment',p_product_id,'Stock adjustment: '||v_product.name||' ('||coalesce(p_reason,'adjustment')||')','posted',v_value,v_value,v_user_id,v_user_id,now()) returning id into v_je;
 if p_quantity_delta>0 then insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit) values(v_org_id,v_je,v_asset,'Inventory gain',v_value,0),(v_org_id,v_je,v_offset,'Positive stock adjustment',0,v_value);
 else insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit) values(v_org_id,v_je,v_offset,'Inventory write-off',v_value,0),(v_org_id,v_je,v_asset,'Inventory reduction',0,v_value); end if;
 update public.stock_movements set movement_type=case when p_quantity_delta>0 then 'adjustment_in' else 'adjustment_out' end,reference_type='adjustment',reference_code='JE/'||v_je::text,notes=left(trim(coalesce(p_notes,'')),1000),created_by=v_user_id where id=(select id from public.stock_movements where organization_id=v_org_id and product_id=p_product_id order by created_at desc limit 1);
 return jsonb_build_object('product_id',p_product_id,'stock_on_hand',v_after,'adjustment_value',v_value,'journal_entry_id',v_je);
end; $$;
revoke all on function public.supplyos_ensure_finance_defaults(uuid) from public,anon,authenticated;
revoke all on function public.supplyos_product_stock_audit() from public,anon,authenticated;
revoke all on function public.supplyos_recalc_payroll_totals() from public,anon,authenticated;
revoke all on function public.supplyos_seed_finance_defaults_trigger() from public,anon,authenticated;
revoke all on function public.save_stock_product(uuid,text,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,boolean,uuid) from public,anon;
revoke all on function public.adjust_stock_balance(uuid,numeric,numeric,uuid,text,text) from public,anon;
grant execute on function public.save_stock_product(uuid,text,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,boolean,uuid) to authenticated;
grant execute on function public.adjust_stock_balance(uuid,numeric,numeric,uuid,text,text) to authenticated;
