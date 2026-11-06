-- Multi-product purchase orders and partial receiving by line.
create or replace function public.create_stock_purchase_order_multi(p_supplier_id uuid,p_warehouse_id uuid,p_items jsonb,p_expected_date date default null,p_notes text default '')
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_po_id uuid;v_line record;v_count integer;v_total numeric(14,2);
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
 if v_org_id is null then raise exception 'No factory workspace is linked to this account.'; end if;
 if not exists(select 1 from public.memberships where organization_id=v_org_id and user_id=v_user_id and role in ('owner','admin','manager','staff')) then raise exception 'You do not have purchasing permission.'; end if;
 if not exists(select 1 from public.suppliers where id=p_supplier_id and organization_id=v_org_id and is_active) then raise exception 'Choose an active supplier.'; end if;
 if not exists(select 1 from public.warehouses where id=p_warehouse_id and organization_id=v_org_id and is_active) then raise exception 'Choose an active warehouse.'; end if;
 if jsonb_typeof(p_items)<>'array' then raise exception 'Add at least one product line.'; end if;
 select count(*) into v_count from jsonb_array_elements(p_items);
 if v_count<1 or v_count>50 then raise exception 'A purchase order must contain 1 to 50 product lines.'; end if;
 if exists(select 1 from jsonb_array_elements(p_items) x where coalesce(x.value->>'product_id','')='' or coalesce((x.value->>'quantity')::numeric,0)<=0 or coalesce((x.value->>'unit_cost')::numeric,-1)<0) then raise exception 'Each product line needs a product, positive quantity, and non-negative unit cost.'; end if;
 if exists(select 1 from jsonb_array_elements(p_items) x where not exists(select 1 from public.products p where p.id=(x.value->>'product_id')::uuid and p.organization_id=v_org_id and p.is_active)) then raise exception 'Every purchase line must use an active product from this workspace.'; end if;
 select round(sum((x.value->>'quantity')::numeric*(x.value->>'unit_cost')::numeric),2) into v_total from jsonb_array_elements(p_items) x;
 insert into public.purchase_orders(organization_id,supplier_id,warehouse_id,expected_date,status,subtotal,notes,created_by)
 values(v_org_id,p_supplier_id,p_warehouse_id,p_expected_date,'ordered',v_total,left(trim(coalesce(p_notes,'')),1000),v_user_id) returning id into v_po_id;
 for v_line in select value from jsonb_array_elements(p_items) loop
  insert into public.purchase_order_items(organization_id,purchase_order_id,product_id,quantity_ordered,unit_cost)
  values(v_org_id,v_po_id,(v_line.value->>'product_id')::uuid,(v_line.value->>'quantity')::numeric,(v_line.value->>'unit_cost')::numeric);
 end loop;
 return v_po_id;
end; $$;

create or replace function public.receive_stock_purchase_order_multi(p_purchase_order_id uuid,p_items jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_org_id uuid;v_po public.purchase_orders%rowtype;v_line record;v_item public.purchase_order_items%rowtype;v_product public.products%rowtype;v_item_id uuid;v_qty numeric;v_value numeric;v_total numeric(14,2):=0;v_inventory uuid;v_ap uuid;v_je uuid;v_count integer;v_all_received boolean;
begin
 if v_user_id is null then raise exception 'Please sign in first.'; end if;
 select organization_id into v_org_id from public.memberships where user_id=v_user_id limit 1;
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

revoke all on function public.create_stock_purchase_order_multi(uuid,uuid,jsonb,date,text) from public,anon;
revoke all on function public.receive_stock_purchase_order_multi(uuid,jsonb) from public,anon;
grant execute on function public.create_stock_purchase_order_multi(uuid,uuid,jsonb,date,text) to authenticated;
grant execute on function public.receive_stock_purchase_order_multi(uuid,jsonb) to authenticated;
