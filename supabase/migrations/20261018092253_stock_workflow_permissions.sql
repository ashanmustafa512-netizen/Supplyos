-- Ensure inventory/purchasing RPCs check both workspace and role, and disable legacy single-line APIs.
create or replace function public.create_stock_supplier(p_supplier_code text,p_name text,p_phone text default '',p_email text default '',p_address text default '',p_city text default '',p_payment_terms_days integer default 30,p_notes text default '')
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_id uuid;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
 if not exists(select 1 from public.memberships where organization_id=v_org_id and user_id=v_user_id and role in ('owner','admin','manager','staff')) then raise exception 'You do not have supplier management permission.'; end if;
 if nullif(trim(p_supplier_code),'') is null or nullif(trim(p_name),'') is null then raise exception 'Supplier code and supplier name are required.'; end if;
 if p_payment_terms_days not between 0 and 365 then raise exception 'Payment terms must be 0–365 days.'; end if;
 insert into public.suppliers(organization_id,supplier_code,name,phone,email,address,city,payment_terms_days,notes)
 values(v_org_id,upper(trim(p_supplier_code)),trim(p_name),left(trim(coalesce(p_phone,'')),40),left(trim(coalesce(p_email,'')),150),left(trim(coalesce(p_address,'')),500),left(trim(coalesce(p_city,'')),100),p_payment_terms_days,left(trim(coalesce(p_notes,'')),1000)) returning id into v_id; return v_id;
exception when unique_violation then raise exception 'That supplier code already exists.'; end; $$;

create or replace function public.create_stock_warehouse(p_code text,p_name text,p_address text default '',p_city text default '',p_contact_name text default '',p_contact_phone text default='',p_is_default boolean default false)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_id uuid;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
 if not exists(select 1 from public.memberships where organization_id=v_org_id and user_id=v_user_id and role in ('owner','admin','manager','staff')) then raise exception 'You do not have warehouse management permission.'; end if;
 if nullif(trim(p_code),'') is null or nullif(trim(p_name),'') is null then raise exception 'Warehouse code and name are required.'; end if;
 if p_is_default then update public.warehouses set is_default=false where organization_id=v_org_id; end if;
 insert into public.warehouses(organization_id,code,name,address,city,contact_name,contact_phone,is_default)
 values(v_org_id,upper(trim(p_code)),trim(p_name),left(trim(coalesce(p_address,'')),500),left(trim(coalesce(p_city,'')),100),left(trim(coalesce(p_contact_name,'')),100),left(trim(coalesce(p_contact_phone,'')),40),coalesce(p_is_default,false)) returning id into v_id; return v_id;
exception when unique_violation then raise exception 'That warehouse code already exists.'; end; $$;

create or replace function public.adjust_stock_balance(p_product_id uuid,p_quantity_delta numeric,p_unit_cost numeric default null,p_warehouse_id uuid default null,p_reason text default 'adjustment',p_notes text default '')
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_product public.products%rowtype;v_after numeric;v_cost numeric;v_asset uuid;v_offset uuid;v_je uuid;v_value numeric;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
 if not exists(select 1 from public.memberships where organization_id=v_org_id and user_id=v_user_id and role in ('owner','admin','manager','staff')) then raise exception 'You do not have stock adjustment permission.'; end if;
 select * into v_product from public.products where id=p_product_id and organization_id=v_org_id for update;
 if not found then raise exception 'Product not found in this workspace.'; end if;
 if p_quantity_delta is null or p_quantity_delta=0 then raise exception 'Adjustment quantity cannot be zero.'; end if;
 if p_unit_cost is not null and p_unit_cost<0 then raise exception 'Unit cost cannot be negative.'; end if;
 if p_unit_cost is not null and p_unit_cost<>v_product.unit_cost and v_product.stock_on_hand>0 then raise exception 'Change the product unit cost in the product editor. The editor posts the required inventory revaluation.'; end if;
 if p_warehouse_id is not null and not exists(select 1 from public.warehouses where id=p_warehouse_id and organization_id=v_org_id and is_active) then raise exception 'Choose an active warehouse.'; end if;
 v_after:=v_product.stock_on_hand+p_quantity_delta;
 if v_after<v_product.stock_reserved then raise exception 'The adjustment would place stock below reserved quantities.'; end if;
 v_cost:=coalesce(p_unit_cost,v_product.unit_cost); v_value:=round(abs(p_quantity_delta)*v_cost,2);
 if p_warehouse_id is not null then perform set_config('supplyos.warehouse_id',p_warehouse_id::text,true); end if;
 update public.products set stock_on_hand=v_after,unit_cost=v_cost where id=p_product_id and organization_id=v_org_id;
 select id into v_asset from public.finance_accounts where organization_id=v_org_id and code='1200';
 if p_quantity_delta>0 then v_offset:=(select id from public.finance_accounts where organization_id=v_org_id and code='4200');
 else v_offset:=(select id from public.finance_accounts where organization_id=v_org_id and code='6600'); end if;
 insert into public.accounting_journal_entries(organization_id,entry_date,source_type,source_id,description,status,debit_total,credit_total,created_by,posted_by,posted_at)
 values(v_org_id,current_date,'stock_adjustment',p_product_id,'Stock adjustment: '||v_product.name||' ('||coalesce(p_reason,'adjustment')||')','posted',v_value,v_value,v_user_id,v_user_id,now()) returning id into v_je;
 if p_quantity_delta>0 then
  insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit)
  values(v_org_id,v_je,v_asset,'Inventory gain',v_value,0),(v_org_id,v_je,v_offset,'Positive stock adjustment',0,v_value);
 else
  insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit)
  values(v_org_id,v_je,v_offset,'Inventory write-off',v_value,0),(v_org_id,v_je,v_asset,'Inventory reduction',0,v_value);
 end if;
 update public.stock_movements set movement_type=case when p_quantity_delta>0 then 'adjustment_in' else 'adjustment_out' end,
  reference_type='adjustment',reference_code='JE/'||v_je::text,notes=left(trim(coalesce(p_notes,'')),1000),created_by=v_user_id
 where id=(select id from public.stock_movements where organization_id=v_org_id and product_id=p_product_id order by created_at desc limit 1);
 return jsonb_build_object('product_id',p_product_id,'stock_on_hand',v_after,'adjustment_value',v_value,'journal_entry_id',v_je);
end; $$;

create or replace function public.receive_stock_purchase_order_multi(p_purchase_order_id uuid,p_items jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_po public.purchase_orders%rowtype;v_line record;v_item public.purchase_order_items%rowtype;v_product public.products%rowtype;v_item_id uuid;v_qty numeric;v_value numeric;v_total numeric(14,2):=0;v_inventory uuid;v_ap uuid;v_je uuid;v_count integer;v_all_received boolean;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
 if not exists(select 1 from public.memberships where organization_id=v_org_id and user_id=v_user_id and role in ('owner','admin','manager','staff')) then raise exception 'You do not have stock receiving permission.'; end if;
 select * into v_po from public.purchase_orders where id=p_purchase_order_id and organization_id=v_org_id for update;
 if not found then raise exception 'Purchase order not found in this workspace.'; end if;
 if v_po.status in ('received','cancelled','draft') then raise exception 'This purchase order cannot be received in its current state.'; end if;
 if jsonb_typeof(p_items)<>'array' then raise exception 'Select at least one purchase order line to receive.'; end if;
 select count(*) into v_count from jsonb_array_elements(p_items);
 if v_count<1 or v_count>50 then raise exception 'Receive between 1 and 50 lines per transaction.'; end if;
 if (select count(distinct x.value->>'item_id') from jsonb_array_elements(p_items) x)<>v_count then raise exception 'A purchase order line can only appear once in a receipt.'; end if;
 for v_line in select value from jsonb_array_elements(p_items) loop
  v_item_id:=(v_line.value->>'item_id')::uuid;v_qty:=(v_line.value->>'quantity')::numeric;
  if v_qty<=0 then raise exception 'Receipt quantities must be positive.'; end if;
  select * into v_item from public.purchase_order_items where id=v_item_id and purchase_order_id=v_po.id and organization_id=v_org_id for update;
  if not found then raise exception 'A receipt line does not belong to this purchase order.'; end if;
  if v_qty>v_item.quantity_ordered-v_item.quantity_received then raise exception 'Receipt quantity exceeds the outstanding quantity for one of the lines.'; end if;
  select * into v_product from public.products where id=v_item.product_id and organization_id=v_org_id for update;
  if not found then raise exception 'A product from this purchase order is no longer available.'; end if;
  v_value:=round(v_qty*v_item.unit_cost,2);perform set_config('supplyos.warehouse_id',v_po.warehouse_id::text,true);
  update public.products set stock_on_hand=stock_on_hand+v_qty,unit_cost=case when stock_on_hand+v_qty>0 then round((stock_on_hand*unit_cost+v_qty*v_item.unit_cost)/(stock_on_hand+v_qty),2) else v_item.unit_cost end where id=v_product.id and organization_id=v_org_id;
  update public.purchase_order_items set quantity_received=quantity_received+v_qty where id=v_item.id;
  update public.stock_movements set reference_type='purchase_order',reference_code=v_po.po_no,notes='Received from purchase order',created_by=v_user_id where id=(select id from public.stock_movements where organization_id=v_org_id and product_id=v_product.id order by created_at desc limit 1);
  v_total:=v_total+v_value;
 end loop;
 select not exists(select 1 from public.purchase_order_items poi where poi.purchase_order_id=v_po.id and poi.quantity_received<poi.quantity_ordered) into v_all_received;
 update public.purchase_orders set received_value=received_value+v_total,status=case when v_all_received then 'received' else 'partially_received' end,received_at=case when v_all_received then now() else received_at end,updated_at=now() where id=v_po.id;
 if v_total>0 then
  select id into v_inventory from public.finance_accounts where organization_id=v_org_id and code='1200';
  select id into v_ap from public.finance_accounts where organization_id=v_org_id and code='2000';
  insert into public.accounting_journal_entries(organization_id,entry_date,source_type,source_id,description,status,debit_total,credit_total,created_by,posted_by,posted_at)
  values(v_org_id,current_date,'purchase_receipt',v_po.id,'Inventory receipt for '||v_po.po_no,'posted',v_total,v_total,v_user_id,v_user_id,now()) returning id into v_je;
  insert into public.accounting_journal_lines(organization_id,journal_entry_id,account_id,description,debit,credit)
  values(v_org_id,v_je,v_inventory,'Stock received: '||v_po.po_no,v_total,0),(v_org_id,v_je,v_ap,'Supplier payable: '||v_po.po_no,0,v_total);
 end if;
 return jsonb_build_object('purchase_order_id',v_po.id,'receipt_value',v_total,'status',(select status from public.purchase_orders where id=v_po.id),'fully_received',v_all_received);
end; $$;

-- The current UI uses validated multi-line workflows; disable older single-line endpoints.
revoke all on function public.create_stock_purchase_order(uuid,uuid,uuid,numeric,numeric,date,text) from public,anon,authenticated;
revoke all on function public.receive_stock_purchase_order(uuid,numeric) from public,anon,authenticated;
revoke all on function public.create_stock_supplier(text,text,text,text,text,text,integer,text) from public,anon;
revoke all on function public.create_stock_warehouse(text,text,text,text,text,text,boolean) from public,anon;
revoke all on function public.adjust_stock_balance(uuid,numeric,numeric,uuid,text,text) from public,anon;
grant execute on function public.create_stock_supplier(text,text,text,text,text,text,integer,text) to authenticated;
grant execute on function public.create_stock_warehouse(text,text,text,text,text,text,boolean) to authenticated;
grant execute on function public.adjust_stock_balance(uuid,numeric,numeric,uuid,text,text) to authenticated;
grant execute on function public.receive_stock_purchase_order_multi(uuid,jsonb) to authenticated;
