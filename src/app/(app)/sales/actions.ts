"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser } from "@/lib/server-auth";
const back=(k:"success"|"error",v:string):never=>redirect(`/sales?${k}=${encodeURIComponent(v)}`);const s=(f:FormData,k:string)=>String(f.get(k)??"").trim();const n=(f:FormData,k:string)=>Number(f.get(k)??0);
export async function issueInvoice(f:FormData){const {supabase}=await requireUser();const {error}=await supabase.rpc("issue_sales_invoice",{p_booking_id:s(f,"booking_id"),p_due_date:s(f,"due_date")||null,p_notes:s(f,"notes")});if(error)back("error",error.message);revalidatePath("/sales");revalidatePath("/accounting");back("success","Invoice created and posted to accounts receivable.");}
export async function recordPayment(f:FormData){const amount=n(f,"amount");if(!(amount>0)||!Number.isFinite(amount))back("error","Payment amount must be positive.");const {supabase}=await requireUser();const {error}=await supabase.rpc("record_sales_payment",{p_invoice_id:s(f,"invoice_id"),p_payment_date:s(f,"payment_date")||null,p_amount:amount,p_payment_method:s(f,"payment_method"),p_reference:s(f,"reference"),p_received_account_code:s(f,"received_account_code")});if(error)back("error",error.message);revalidatePath("/sales");revalidatePath("/accounting");revalidatePath("/customers");back("success","Payment recorded, invoice balance updated and receipt posted.");}
export async function createRecoveryTask(f: FormData) {
  const { supabase } = await requireUser();
  const { error } = await supabase.rpc("create_sales_recovery_task", {
    p_customer_id: s(f, "customer_id"), p_invoice_id: s(f, "invoice_id") || null,
    p_due_date: s(f, "due_date") || null, p_priority: s(f, "priority") || "medium",
    p_task_type: s(f, "task_type") || "call", p_summary: s(f, "summary"), p_notes: s(f, "notes"),
  });
  if (error) back("error", error.message);
  revalidatePath("/sales"); back("success", "Recovery follow-up added to the collection queue.");
}
export async function updateRecoveryTask(f: FormData) {
  const { supabase } = await requireUser();
  const { error } = await supabase.rpc("update_sales_recovery_task", {
    p_task_id: s(f, "task_id"), p_status: s(f, "status"), p_outcome: s(f, "outcome"), p_next_action_at: s(f, "next_action_at") || null,
  });
  if (error) back("error", error.message);
  revalidatePath("/sales"); back("success", "Recovery task updated.");
}
