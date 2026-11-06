-- Stock, supplier, warehouse, purchasing, and adjustment workflows.
create or replace function public.save_stock_product(
 p_product_id uuid,p_sku text,p_name text,p_unit text,p_category text,p_barcode text,
 p_unit_cost numeric,p_unit_price numeric,p_stock_on_hand numeric,p_unit_weight_kg numeric,
 p_raw_material_cost numeric,p_direct_labor_cost numeric,p_production_overhead numeric,p_reorder_level numeric,
 p_is_active boolean,p_default_supplier_id uuid
) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid(); v_org_id uuid; v_product_id uuid; v_existing public.products%rowtype; v_je uuid; v_production_cost numeric(14,2); v_value numeric(14,2);
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select m.organization_id into v_org_id from public.memberships m where m.user_id=v_user_id limit 1;
 if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
 if not exists(select 1 from public.memberships m where m.organization_id=v_org_id and m.user_id=v_user_id and m.role in ('owner','admin','manager','staff')) then raise exception 'You do not have inventory editing permission.'; end if;
 if nullif(trim(p_sku),'') is null or nullif(trim(p_name),'') is null then raise exception 'SKU and product name are required.'; end if;
 if least(coalesce(p_unit_cost,-1),coalesce(p_unit_price,-1),coalesce(p_stock_on_hand,-1),coalesce(p_unit_weight_kg,-1),coalesce(p_raw_material_cost,-1),coalesce(p_direct_labor_cost,-1),coalesce(p_production_overhead,-1),coalesce(p_reorder_level,-1))<0 then raise exception 'Cost, price, stock, weight, production components, and reorder level must be non-negative.'; end if;
 if p_default_supplier_id is not null and not exists(select 1 from public.suppliers s where s.id=p_default_supplier_id and s.organization_id=v_org_id and s.is_active) then raise exception 'Choose an active supplier from this workspace.'; end if;
 v_production_cost:=round(coalesce(p_raw_material_cost,0)+coalesce(p_direct_labor_cost,0)+coalesce(p_production_overhead,0),2);
 if p_product_id is null then
  insert into public.products(organization_id,sku,name,unit,unit_cost,unit_price,stock_on_hand,unit_weight_kg,is_active,category,barcode,raw_material_cost,direct_labor_cost,production_overhead,production_cost,reorder_level,default_supplier_id)
  values(v_org_id,upper(trim(p_sku)),trim(p_name),coalesce(nullif(trim(p_unit),''),'unit'),p_unit_cost,p_unit_price,p_stock_on_hand,p_unit_weight_kg,coalesce(p_is_active,true),coalesce(nullif(trim(p_category),''),'General'),trim(coalesce(p_barcode,'')),p_raw_material_cost,p_direct_labor_cost,p_production_overhead,v_production_cost,p_reorder_level,p_default_supplier_id) returning id into v_product_id;
  v_value:=round(p_stock_on_hand*p_unit_cost,2);
  if v_value>0 then
   insert into public.accounting_journal_entries(organization_id,entry_date,source_type,source_id,description,status,debit_total,credit_total,created_by,posted_by,posted_at)
   values(v_org_id,current_date,'stock_opening',v_product_id,'Opening inventory - '||trim(p_name),'posted',v_value,v_value,v_user_id,v_user_id,now()) returning id into v_je;
   insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit)
   select v_org_id,v_je,a.id,'Opening stock: '||trim(p_name),v_value,0 from public.finance_accounts a where a.organization_id=v_org_id and a.code='1200';
   insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit)
   select v_org_id,v_je,a.id,'Opening stock offset: '||trim(p_name),0,v_value from public.finance_accounts a where a.organization_id=v_org_id and a.code='3000';
  end if;
 else
  select * into v_existing from public.products p where p.id=p_product_id and p.organization_id=v_org_id for update;
  if not found then raise exception 'Product not found in this workspace.'; end if;
  if p_stock_on_hand<v_existing.stock_reserved then raise exception 'On-hand stock cannot be less than already reserved units.'; end if;
  update public.products set sku=upper(trim(p_sku)),name=trim(p_name),unit=coalesce(nullif(trim(p_unit),''),'unit'),unit_cost=p_unit_cost,unit_price=p_unit_price,stock_on_hand=p_stock_on_hand,unit_weight_kg=p_unit_weight_kg,is_active=coalesce(p_is_active,true),category=coalesce(nullif(trim(p_category),''),'General'),barcode=trim(coalesce(p_barcode,'')),raw_material_cost=p_raw_material_cost,direct_labor_cost=p_direct_labor_cost,production_overhead=p_production_overhead,production_cost=v_production_cost,reorder_level=p_reorder_level,default_supplier_id=p_default_supplier_id where id=p_product_id and organization_id=v_org_id returning id into v_product_id;
 end if;
 return v_product_id;
exception when unique_violation then raise exception 'That SKU already exists in this workspace.'; end; $$;

create or replace function public.create_stock_supplier(p_supplier_code text,p_name text,p_phone text default '',p_email text default='',p_address text default='',p_city text default='',p_payment_terms_days integer default 30,p_notes text default='')
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_id uuid;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
 if nullif(trim(p_supplier_code),'') is null or nullif(trim(p_name),'') is null then raise exception 'Supplier code and supplier name are required.'; end if;
 if p_payment_terms_days not between 0 and 365 then raise exception 'Payment terms must be 0–365 days.'; end if;
 insert into public.suppliers(organization_id,supplier_code,name,phone,email,address,city,payment_terms_days,notes)
 values(v_org_id,upper(trim(p_supplier_code)),trim(p_name),left(trim(coalesce(p_phone,'')),40),left(trim(coalesce(p_email,'')),150),left(trim(coalesce(p_address,'')),500),left(trim(coalesce(p_city,'')),100),p_payment_terms_days,left(trim(coalesce(p_notes,'')),1000)) returning id into v_id; return v_id;
exception when unique_violation then raise exception 'That supplier code already exists.'; end; $$;

create or replace function public.create_stock_warehouse(p_code text,p_name text,p_address text default='',p_city text default='',p_contact_name text default='',p_contact_phone text default='',p_is_default boolean default false)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_id uuid;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
 if nullif(trim(p_code),'') is null or nullif(trim(p_name),'') is null then raise exception 'Warehouse code and name are required.'; end if;
 if p_is_default then update public.warehouses set is_default=false where organization_id=v_org_id; end if;
 insert into public.warehouses(organization_id,code,name,address,city,contact_name,contact_phone,is_default)
 values(v_org_id,upper(trim(p_code)),trim(p_name),left(trim(coalesce(p_address,'')),500),left(trim(coalesce(p_city,'')),100),left(trim(coalesce(p_contact_name,'')),100),left(trim(coalesce(p_contact_phone,'')),40),coalesce(p_is_default,false)) returning id into v_id; return v_id;
exception when unique_violation then raise exception 'That warehouse code already exists.'; end; $$;

create or replace function public.create_stock_purchase_order(p_supplier_id uuid,p_warehouse_id uuid,p_product_id uuid,p_quantity numeric,p_unit_cost numeric,p_expected_date date default null,p_notes text default '')
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_id uuid;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
 if p_quantity is null or p_quantity<=0 or p_unit_cost is null or p_unit_cost<0 then raise exception 'Enter a positive quantity and non-negative unit cost.'; end if;
 if not exists(select 1 from public.suppliers where id=p_supplier_id and organization_id=v_org_id and is_active) then raise exception 'Choose an active supplier.'; end if;
 if not exists(select 1 from public.warehouses where id=p_warehouse_id and organization_id=v_org_id and is_active) then raise exception 'Choose an active warehouse.'; end if;
 if not exists(select 1 from public.products where id=p_product_id and organization_id=v_org_id and is_active) then raise exception 'Choose an active product.'; end if;
 insert into public.purchase_orders(organization_id,supplier_id,warehouse_id,expected_date,status,subtotal,notes,created_by)
 values(v_org_id,p_supplier_id,p_warehouse_id,p_expected_date,'ordered',round(p_quantity*p_unit_cost,2),left(trim(coalesce(p_notes,'')),1000),v_user_id) returning id into v_id;
 insert into public.purchase_order_items(organization_id,purchase_order_id,product_id,quantity_ordered,unit_cost) values(v_org_id,v_id,p_product_id,p_quantity,p_unit_cost);
 return v_id;
end; $$;

create or replace function public.receive_stock_purchase_order(p_purchase_order_id uuid,p_quantity numeric default null)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_po public.purchase_orders%rowtype;v_item public.purchase_order_items%rowtype;v_qty numeric;v_value numeric;v_product public.products%rowtype;v_je uuid;v_inventory uuid;v_ap uuid;v_already numeric;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 select * into v_po from public.purchase_orders where id=p_purchase_order_id and organization_id=v_org_id for update;
 if not found then raise exception 'Purchase order not found in this workspace.'; end if;
 if v_po.status in ('received','cancelled','draft') then raise exception 'This purchase order cannot be received in its current state.'; end if;
 select * into v_item from public.purchase_order_items where purchase_order_id=v_po.id limit 1 for update;
 if not found then raise exception 'Purchase order has no item line.'; end if;
 v_qty:=coalesce(p_quantity,v_item.quantity_ordered-v_item.quantity_received);
 if v_qty<=0 or v_qty>v_item.quantity_ordered-v_item.quantity_received then raise exception 'Receipt quantity must be positive and no greater than the outstanding order quantity.'; end if;
 select * into v_product from public.products where id=v_item.product_id and organization_id=v_org_id for update;
 v_value:=round(v_qty*v_item.unit_cost,2); v_already:=v_item.quantity_received;
 perform set_config('supplyos.warehouse_id',v_po.warehouse_id::text,true);
 update public.products set stock_on_hand=stock_on_hand+v_qty,unit_cost=case when stock_on_hand+v_qty>0 then round((stock_on_hand*unit_cost+v_qty*v_item.unit_cost)/(stock_on_hand+v_qty),2) else v_item.unit_cost end where id=v_product.id and organization_id=v_org_id;
 update public.purchase_order_items set quantity_received=quantity_received+v_qty where id=v_item.id;
 update public.purchase_orders set received_value=received_value+v_value,status=case when v_already+v_qty>=v_item.quantity_ordered then 'received' else 'partially_received' end,received_at=case when v_already+v_qty>=v_item.quantity_ordered then now() else received_at end,updated_at=now() where id=v_po.id;
 select id into v_inventory from public.finance_accounts where organization_id=v_org_id and code='1200';
 select id into v_ap from public.finance_accounts where organization_id=v_org_id and code='2000';
 insert into public.accounting_journal_entries(organization_id,entry_date,source_type,source_id,description,status,debit_total,credit_total,created_by,posted_by,posted_at)
 values(v_org_id,current_date,'purchase_receipt',v_po.id,'Inventory receipt for '||v_po.po_no,'posted',v_value,v_value,v_user_id,v_user_id,now()) returning id into v_je;
 insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit) values(v_org_id,v_je,v_inventory,'Stock received: '||v_product.name,v_value,0),(v_org_id,v_je,v_ap,'Supplier payable: '||v_po.po_no,0,v_value);
 update public.stock_movements set reference_type='purchase_order',reference_code=v_po.po_no,notes='Received from purchase order',created_by=v_user_id where id=(select id from public.stock_movements where organization_id=v_org_id and product_id=v_product.id order by created_at desc limit 1);
 return jsonb_build_object('purchase_order_id',v_po.id,'received_quantity',v_qty,'received_value',v_value,'status',(select status from public.purchase_orders where id=v_po.id));
end; $$;

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
 if p_warehouse_id is not null and not exists(select 1 from public.warehouses where id=p_warehouse_id and organization_id=v_org_id and is_active) then raise exception 'Choose an active warehouse.'; end if;
 v_after:=v_product.stock_on_hand+p_quantity_delta;
 if v_after<v_product.stock_reserved then raise exception 'The adjustment would place stock below reserved quantities.'; end if;
 v_cost:=coalesce(p_unit_cost,v_product.unit_cost); v_value:=round(abs(p_quantity_delta)*v_cost,2);
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

revoke all on function public.save_stock_product(uuid,text,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,boolean,uuid) from public,anon;
revoke all on function public.create_stock_supplier(text,text,text,text,text,text,integer,text) from public,anon;
revoke all on function public.create_stock_warehouse(text,text,text,text,text,text,boolean) from public,anon;
revoke all on function public.create_stock_purchase_order(uuid,uuid,uuid,numeric,numeric,date,text) from public,anon;
revoke all on function public.receive_stock_purchase_order(uuid,numeric) from public,anon;
revoke all on function public.adjust_stock_balance(uuid,numeric,numeric,uuid,text,text) from public,anon;
grant execute on function public.save_stock_product(uuid,text,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,boolean,uuid) to authenticated;
grant execute on function public.create_stock_supplier(text,text,text,text,text,text,integer,text) to authenticated;
grant execute on function public.create_stock_warehouse(text,text,text,text,text,text,boolean) to authenticated;
grant execute on function public.create_stock_purchase_order(uuid,uuid,uuid,numeric,numeric,date,text) to authenticated;
grant execute on function public.receive_stock_purchase_order(uuid,numeric) to authenticated;
grant execute on function public.adjust_stock_balance(uuid,numeric,numeric,uuid,text,text) to authenticated;
