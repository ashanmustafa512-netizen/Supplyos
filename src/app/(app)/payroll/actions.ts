"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser } from "@/lib/server-auth";
const back=(k:"success"|"error",v:string):never=>redirect(`/payroll?${k}=${encodeURIComponent(v)}`);const s=(f:FormData,k:string)=>String(f.get(k)??"").trim();const n=(f:FormData,k:string)=>Number(f.get(k)??0);
export async function addEmployee(f:FormData){const {supabase}=await requireUser();const {error}=await supabase.rpc("add_payroll_employee",{p_employee_no:s(f,"employee_no").toUpperCase(),p_full_name:s(f,"full_name"),p_department:s(f,"department"),p_designation:s(f,"designation"),p_email:s(f,"email"),p_phone:s(f,"phone"),p_hire_date:s(f,"hire_date")||null,p_monthly_basic:n(f,"monthly_basic"),p_housing_allowance:n(f,"housing_allowance"),p_transport_allowance:n(f,"transport_allowance"),p_other_allowance:n(f,"other_allowance"),p_fixed_deduction:n(f,"fixed_deduction"),p_tax_percent:n(f,"tax_percent"),p_employment_type:s(f,"employment_type")||"full_time"});if(error)back("error",error.message);revalidatePath("/payroll");back("success","Employee added to the payroll directory.");}
export async function createRun(f:FormData){const {supabase}=await requireUser();const {error}=await supabase.rpc("create_monthly_payroll_run",{p_period_start:s(f,"period_start")||new Date().toISOString().slice(0,10),p_notes:s(f,"notes")});if(error)back("error",error.message);revalidatePath("/payroll");back("success","Draft payroll run created. Review each employee line before approval.");}
export async function updateItem(f:FormData){const {supabase}=await requireUser();const {error}=await supabase.rpc("update_payroll_item",{p_item_id:s(f,"item_id"),p_overtime_hours:n(f,"overtime_hours"),p_overtime_amount:n(f,"overtime_amount"),p_bonus:n(f,"bonus"),p_deductions:n(f,"deductions"),p_tax_withheld:n(f,"tax_withheld"),p_notes:s(f,"notes")});if(error)back("error",error.message);revalidatePath("/payroll");back("success","Payroll line updated and totals recalculated.");}
export async function runAction(f:FormData){const action=s(f,"action");const {supabase}=await requireUser();const {error}=await supabase.rpc("payroll_run_action",{p_run_id:s(f,"run_id"),p_action:action,p_payment_account_code:s(f,"payment_account_code")||"1010"});if(error)back("error",error.message);revalidatePath("/payroll");revalidatePath("/accounting");back("success",action==="approve"?"Payroll approved and accrued to the ledger.":action==="pay"?"Payroll marked paid and bank payment posted.":"Draft payroll run voided.");}
export async function updateEmployee(f: FormData) {
  const { supabase } = await requireUser();
  const { error } = await supabase.rpc("update_payroll_employee", {
    p_employee_id: s(f, "employee_id"), p_department: s(f, "department"), p_designation: s(f, "designation"),
    p_monthly_basic: n(f, "monthly_basic"), p_housing_allowance: n(f, "housing_allowance"),
    p_transport_allowance: n(f, "transport_allowance"), p_other_allowance: n(f, "other_allowance"),
    p_fixed_deduction: n(f, "fixed_deduction"), p_tax_percent: n(f, "tax_percent"), p_status: s(f, "status"),
  });
  if (error) back("error", error.message);
  revalidatePath("/payroll"); back("success", "Employee payroll profile updated.");
}
