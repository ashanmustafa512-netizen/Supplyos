"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser } from "@/lib/server-auth";
const back=(key:"success"|"error",v:string):never=>redirect(`/accounting?${key}=${encodeURIComponent(v)}`);
const s=(f:FormData,k:string)=>String(f.get(k)??"").trim();const n=(f:FormData,k:string)=>Number(f.get(k)??0);
export async function addExpense(f:FormData){const amount=n(f,"amount");if(!(amount>0)||!Number.isFinite(amount)||!s(f,"description"))back("error","Enter a description and positive expense amount.");const {supabase}=await requireUser();const {error}=await supabase.rpc("record_finance_expense",{p_date:s(f,"expense_date")||null,p_expense_account_code:s(f,"expense_account_code"),p_paid_from_account_code:s(f,"paid_from_account_code"),p_amount:amount,p_description:s(f,"description"),p_vendor:s(f,"vendor"),p_payment_method:s(f,"payment_method")||"bank_transfer",p_reference:s(f,"reference")});if(error)back("error",error.message);revalidatePath("/accounting");revalidatePath("/dashboard");back("success","Expense recorded and posted to the ledger.");}
export async function addOtherIncome(f:FormData){const amount=n(f,"amount");if(!(amount>0)||!Number.isFinite(amount)||!s(f,"description"))back("error","Enter a description and positive income amount.");const {supabase}=await requireUser();const {error}=await supabase.rpc("record_other_income",{p_date:s(f,"income_date")||null,p_received_account_code:s(f,"received_account_code"),p_amount:amount,p_description:s(f,"description"),p_reference:s(f,"reference")});if(error)back("error",error.message);revalidatePath("/accounting");back("success","Other income recorded and posted to the ledger.");}
export async function postManualJournal(f: FormData) {
  const amount = n(f, "amount");
  const debitCode = s(f, "debit_account_code");
  const creditCode = s(f, "credit_account_code");
  if (!(amount > 0) || !Number.isFinite(amount) || !s(f, "description")) back("error", "Enter a description and positive journal amount.");
  if (!debitCode || !creditCode || debitCode === creditCode) back("error", "Choose two different accounts for the debit and credit.");
  const { supabase } = await requireUser();
  const { data: selected, error: accountError } = await supabase.from("finance_accounts").select("id,code,name").eq("is_active", true).in("code", [debitCode, creditCode]);
  if (accountError) back("error", accountError.message);
  const debit = selected?.find((a: any) => a.code === debitCode);
  const credit = selected?.find((a: any) => a.code === creditCode);
  if (!debit || !credit) back("error", "Choose active accounts from your chart of accounts.");
  const amountRounded = Math.round((amount + Number.EPSILON) * 100) / 100;
  const { error } = await supabase.rpc("create_manual_journal", {
    p_date: s(f, "entry_date") || null,
    p_description: s(f, "description"),
    p_lines: [
      { account_id: debit.id, description: `${debit.name} — debit`, debit: amountRounded, credit: 0 },
      { account_id: credit.id, description: `${credit.name} — credit`, debit: 0, credit: amountRounded },
    ],
  });
  if (error) back("error", error.message);
  revalidatePath("/accounting"); back("success", "Balanced manual journal posted to the ledger.");
}
