"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser, requireWorkspaceRole } from "@/lib/server-auth";

function withMessage(path: string, key: "error" | "success", value: string) {
  return `${path}?${key}=${encodeURIComponent(value)}`;
}

function refreshBookingViews() {
  revalidatePath("/dashboard");
  revalidatePath("/bookings");
  revalidatePath("/customers");
  revalidatePath("/inventory");
}

export async function createBooking(formData: FormData) {
  const customerId = String(formData.get("customer_id") ?? "");
  const productId = String(formData.get("product_id") ?? "");
  const quantity = Number(formData.get("quantity"));
  const notes = String(formData.get("notes") ?? "").trim().slice(0, 2000);

  if (!customerId || !productId || !Number.isFinite(quantity) || quantity <= 0) {
    redirect(withMessage("/bookings/new", "error", "Select a customer and product, and enter a quantity greater than zero."));
  }

  const { supabase } = await requireUser();
  const { data: bookingId, error } = await supabase.rpc("create_booking", {
    p_customer_id: customerId,
    p_product_id: productId,
    p_quantity: quantity,
    p_notes: notes,
  });

  if (error || !bookingId) {
    redirect(withMessage("/bookings/new", "error", error?.message ?? "Could not create this booking."));
  }
  refreshBookingViews();
  redirect(withMessage("/bookings", "success", "Booking created and sent for approval."));
}

export async function bookingAction(formData: FormData) {
  const bookingId = String(formData.get("booking_id") ?? "");
  const action = String(formData.get("action") ?? "");
  const allowed = new Set(["approve", "reject", "cancel", "complete"]);
  if (!bookingId || !allowed.has(action)) redirect(withMessage("/bookings", "error", "Invalid booking action."));

  const { supabase } = await requireUser();
  const { error } = await supabase.rpc("booking_action", {
    p_booking_id: bookingId,
    p_action: action,
  });
  if (error) redirect(withMessage("/bookings", "error", error.message));

  refreshBookingViews();
  const labels: Record<string, string> = {
    approve: "Booking approved.",
    reject: "Booking rejected.",
    cancel: "Booking cancelled.",
    complete: "Booking marked complete; stock updated.",
  };
  redirect(withMessage("/bookings", "success", labels[action]));
}

/**
 * Bulk approvals intentionally call the existing database workflow once per booking.
 * Each booking therefore still runs its own credit-limit and stock checks. Some can
 * succeed while others fail; the response reports both counts instead of implying
 * that the whole batch was atomic.
 */
export async function bulkApproveBookings(formData: FormData) {
  const rawIds = formData.getAll("booking_ids").map(value => String(value));
  const ids = [...new Set(rawIds)].filter(id => /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id));
  if (!ids.length) {
    redirect(withMessage("/bookings", "error", "Select at least one pending booking to approve."));
  }
  if (ids.length > 100) {
    redirect(withMessage("/bookings", "error", "Bulk approval is limited to 100 bookings per batch."));
  }

  const { supabase } = await requireUser();
  let approved = 0;
  const failures: string[] = [];

  for (const id of ids) {
    const { error } = await supabase.rpc("booking_action", {
      p_booking_id: id,
      p_action: "approve",
    });
    if (error) {
      failures.push(error.message);
    } else {
      approved += 1;
    }
  }

  if (approved > 0) refreshBookingViews();

  if (failures.length === 0) {
    redirect(withMessage("/bookings", "success", `Approved ${approved} booking${approved === 1 ? "" : "s"}. Stock and credit checks passed for every selected booking.`));
  }

  const issue = failures[0].replace(/\s+/g, " ").slice(0, 170);
  const summary = `Approved ${approved}; ${failures.length} failed. Failed bookings stay pending. First issue: ${issue}`;
  redirect(withMessage("/bookings", "error", summary));
}


export type BulkApprovalInlineResult = {
  approvedIds: string[];
  failures: { id: string; message: string }[];
};

/** In-place version used by the booking grid. Every order still invokes the same
 * membership-checked credit and stock reservation transaction independently. */
export async function bulkApproveBookingsInline(rawIds: string[]): Promise<BulkApprovalInlineResult> {
  const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  const ids = [...new Set((Array.isArray(rawIds) ? rawIds : []).filter(id => typeof id === "string" && uuidPattern.test(id)))];
  if (!ids.length || ids.length > 100 || ids.length !== rawIds.length) {
    return { approvedIds: [], failures: [{ id: "", message: "Select between 1 and 100 valid, distinct pending bookings." }] };
  }
  const { supabase } = await requireUser();
  const approvedIds: string[] = [];
  const failures: { id: string; message: string }[] = [];
  for (const id of ids) {
    const { error } = await supabase.rpc("booking_action", { p_booking_id: id, p_action: "approve" });
    if (error) failures.push({ id, message: error.message });
    else approvedIds.push(id);
  }
  if (approvedIds.length) {
    // Keep /bookings in-place: its client state is updated from the response.
    revalidatePath("/dashboard");
    revalidatePath("/customers");
    revalidatePath("/inventory");
  }
  return { approvedIds, failures };
}


/** Shop records are maintained inside the booking workflow, not a standalone Customers tab. */
export async function createBookingShop(formData: FormData) {
  const customerCode = String(formData.get("customer_code") ?? "").trim().toUpperCase();
  const name = String(formData.get("name") ?? "").trim();
  const city = String(formData.get("city") ?? "").trim();
  const region = String(formData.get("region") ?? "").trim();
  const phone = String(formData.get("phone") ?? "").trim();
  const creditLimit = Number(formData.get("credit_limit") ?? 0);

  if (!customerCode || !name || !Number.isFinite(creditLimit) || creditLimit < 0) {
    redirect(withMessage("/bookings/new-shop", "error", "Enter a shop code, shop name and valid non-negative credit limit."));
  }

  const { supabase, organization, membership } = await requireWorkspaceRole(["owner", "admin", "manager"]);
  if (!organization || !membership) {
    redirect(withMessage("/bookings/new-shop", "error", "No factory workspace is linked to this account."));
  }

  const { error } = await supabase.from("customers").insert({
    organization_id: organization.id,
    customer_code: customerCode,
    name,
    city,
    region,
    phone,
    credit_limit: creditLimit,
    score: 75,
  });

  if (error) {
    redirect(withMessage("/bookings/new-shop", "error", error.code === "23505"
      ? "That shop code already exists in this factory."
      : error.message));
  }

  revalidatePath("/bookings/new");
  revalidatePath("/bookings");
  redirect(withMessage("/bookings/new", "success", "Shop added. Select it in your new booking."));
}
