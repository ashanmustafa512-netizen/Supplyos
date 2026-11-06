"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser } from "@/lib/server-auth";
const go=(k:"success"|"error",v:string):never=>redirect(`/inventory?${k}=${encodeURIComponent(v)}`);
const s=(f:FormData,k:string,d="")=>String(f.get(k)??d).trim();
const n=(f:FormData,k:string,d="0")=>Number(f.get(k)??d);
const nullable=(v:string)=>v||null;
export async function createProduct(f:FormData){
 const sku=s(f,"sku").toUpperCase(),name=s(f,"name"); const a=["unit_cost","unit_price","stock_on_hand","unit_weight_kg","raw_material_cost","direct_labor_cost","production_overhead","reorder_level"].map(k=>n(f,k));
 if(!sku||!name||!a.every(v=>Number.isFinite(v)&&v>=0))go("error","Enter SKU, product name and valid non-negative stock and cost values.");
 const {supabase}=await requireUser(); const {error}=await supabase.rpc("save_stock_product",{p_product_id:null,p_sku:sku,p_name:name,p_unit:s(f,"unit","unit"),p_category:s(f,"category","General"),p_barcode:s(f,"barcode"),p_unit_cost:a[0],p_unit_price:a[1],p_stock_on_hand:a[2],p_unit_weight_kg:a[3],p_raw_material_cost:a[4],p_direct_labor_cost:a[5],p_production_overhead:a[6],p_reorder_level:a[7],p_is_active:true,p_default_supplier_id:nullable(s(f,"default_supplier_id"))});
 if(error)go("error",error.message); revalidatePath("/inventory");revalidatePath("/bookings");revalidatePath("/accounting");go("success","Product saved with cost, price and opening-stock ledger entries.");
}
export async function updateProduct(f:FormData){
 const id=s(f,"product_id"),sku=s(f,"sku").toUpperCase(),name=s(f,"name");const a=["unit_cost","unit_price","stock_on_hand","unit_weight_kg","raw_material_cost","direct_labor_cost","production_overhead","reorder_level"].map(k=>n(f,k));
 if(!id||!sku||!name||!a.every(v=>Number.isFinite(v)&&v>=0))go("error","Enter valid product details and non-negative values.");
 const {supabase}=await requireUser();const {error}=await supabase.rpc("save_stock_product",{p_product_id:id,p_sku:sku,p_name:name,p_unit:s(f,"unit","unit"),p_category:s(f,"category","General"),p_barcode:s(f,"barcode"),p_unit_cost:a[0],p_unit_price:a[1],p_stock_on_hand:a[2],p_unit_weight_kg:a[3],p_raw_material_cost:a[4],p_direct_labor_cost:a[5],p_production_overhead:a[6],p_reorder_level:a[7],p_is_active:s(f,"is_active","true")==="true",p_default_supplier_id:nullable(s(f,"default_supplier_id"))});
 if(error)go("error",error.message);revalidatePath("/inventory");revalidatePath("/bookings");revalidatePath("/accounting");go("success","Product details and any required inventory revaluation were saved.");
}
export async function createSupplier(f:FormData){const {supabase}=await requireUser();const {error}=await supabase.rpc("create_stock_supplier",{p_supplier_code:s(f,"supplier_code").toUpperCase(),p_name:s(f,"name"),p_phone:s(f,"phone"),p_email:s(f,"email"),p_address:s(f,"address"),p_city:s(f,"city"),p_payment_terms_days:n(f,"payment_terms_days","30"),p_notes:s(f,"notes")});if(error)go("error",error.message);revalidatePath("/inventory");go("success","Supplier added.");}
export async function createWarehouse(f:FormData){const {supabase}=await requireUser();const {error}=await supabase.rpc("create_stock_warehouse",{p_code:s(f,"code").toUpperCase(),p_name:s(f,"name"),p_address:s(f,"address"),p_city:s(f,"city"),p_contact_name:s(f,"contact_name"),p_contact_phone:s(f,"contact_phone"),p_is_default:s(f,"is_default")==="on"});if(error)go("error",error.message);revalidatePath("/inventory");go("success","Warehouse added.");}
export async function createPurchaseOrder(f:FormData){
 const items:{product_id:string;quantity:number;unit_cost:number}[]=[];
 for(let i=1;i<=50;i++){const product=s(f,`product_id_${i}`),qtyText=s(f,`quantity_${i}`),costText=s(f,`unit_cost_${i}`);if(!product&&!qtyText&&!costText)continue;const qty=Number(qtyText),cost=Number(costText);if(!product||!qtyText||!costText||!(qty>0)||cost<0||!Number.isFinite(qty+cost))go("error",`Purchase line ${i} needs a product, positive quantity and non-negative unit cost.`);items.push({product_id:product,quantity:qty,unit_cost:cost});}
 if(!items.length)go("error","Add at least one product line to this purchase order.");
 const {supabase}=await requireUser();const {error}=await supabase.rpc("create_stock_purchase_order_multi",{p_supplier_id:s(f,"supplier_id"),p_warehouse_id:s(f,"warehouse_id"),p_items:items,p_expected_date:nullable(s(f,"expected_date")),p_notes:s(f,"notes")});
 if(error)go("error",error.message);revalidatePath("/inventory");revalidatePath("/accounting");go("success",`Purchase order created with ${items.length} product line${items.length===1?"":"s"}.`);
}
export async function receivePurchaseOrder(f:FormData){
 const items:{item_id:string;quantity:number}[]=[];
 for(let i=1;i<=50;i++){const item=s(f,`item_id_${i}`),qtyText=s(f,`quantity_${i}`);if(!item)continue;if(!qtyText)continue;const qty=Number(qtyText);if(!(qty>0)||!Number.isFinite(qty))go("error",`Receipt quantity for line ${i} must be positive.`);items.push({item_id:item,quantity:qty});}
 if(!items.length)go("error","Enter a positive receipt quantity for at least one outstanding line.");
 const {supabase}=await requireUser();const {error}=await supabase.rpc("receive_stock_purchase_order_multi",{p_purchase_order_id:s(f,"purchase_order_id"),p_items:items});
 if(error)go("error",error.message);revalidatePath("/inventory");revalidatePath("/accounting");go("success",`Receipt posted for ${items.length} line${items.length===1?"":"s"}; stock and accounting updated.`);
}
export async function adjustStock(f:FormData){const delta=n(f,"quantity_delta"),ct=s(f,"unit_cost"),cost=ct?Number(ct):null;if(!Number.isFinite(delta)||delta===0||(cost!==null&&(!Number.isFinite(cost)||cost<0)))go("error","Enter a non-zero quantity adjustment and valid optional unit cost.");const {supabase}=await requireUser();const {error}=await supabase.rpc("adjust_stock_balance",{p_product_id:s(f,"product_id"),p_quantity_delta:delta,p_unit_cost:cost,p_warehouse_id:nullable(s(f,"warehouse_id")),p_reason:s(f,"reason","adjustment"),p_notes:s(f,"notes")});if(error)go("error",error.message);revalidatePath("/inventory");revalidatePath("/accounting");revalidatePath("/bookings");go("success","Stock adjustment saved and journal entry posted.");}
