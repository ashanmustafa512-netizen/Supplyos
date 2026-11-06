"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser } from "@/lib/server-auth";

const messageUrl = (key: string, value: string) => `/customers?${key}=${encodeURIComponent(value)}`;

export async function createCustomer(formData: FormData) {
  const customerCode = String(formData.get("customer_code") ?? "").trim().toUpperCase();
  const name = String(formData.get("name") ?? "").trim();
  const city = String(formData.get("city") ?? "").trim();
  const region = String(formData.get("region") ?? "").trim();
  const phone = String(formData.get("phone") ?? "").trim();
  const creditLimit = Number(formData.get("credit_limit") ?? 0);
  const score = Number(formData.get("score") ?? 75);
  if (!customerCode || !name || !Number.isFinite(creditLimit) || creditLimit < 0 || !Number.isInteger(score) || score < 0 || score > 100) {
    redirect(messageUrl("error", "Enter a customer code, name, valid credit limit, and score from 0–100."));
  }
  const { supabase, user } = await requireUser();
  const { data: membership } = await supabase.from("memberships").select("organization_id").eq("user_id", user.id).maybeSingle();
  if (!membership) redirect(messageUrl("error", "No factory workspace is linked to this user."));
  const { error } = await supabase.from("customers").insert({
    organization_id: membership.organization_id,
    customer_code: customerCode,
    name,
    city,
    region,
    phone,
    credit_limit: creditLimit,
    score,
  });
  if (error) redirect(messageUrl("error", error.code === "23505" ? "That customer code already exists in this workspace." : error.message));
  revalidatePath("/customers");
  redirect(messageUrl("success", "Customer added."));
}

export async function updateCustomerRules(formData: FormData) {
  const customerId = String(formData.get("customer_id") ?? "");
  const score = Number(formData.get("score"));
  const creditLimit = Number(formData.get("credit_limit"));
  if (!customerId || !Number.isInteger(score) || score < 0 || score > 100 || !Number.isFinite(creditLimit) || creditLimit < 0) {
    redirect(messageUrl("error", "Enter a score between 0–100 and a valid non-negative credit limit."));
  }
  const { supabase } = await requireUser();
  const { error } = await supabase.from("customers").update({ score, credit_limit: creditLimit }).eq("id", customerId);
  if (error) redirect(messageUrl("error", error.message));
  revalidatePath("/customers");
  revalidatePath("/bookings");
  redirect(messageUrl("success", "Customer score and credit limit updated."));
}
