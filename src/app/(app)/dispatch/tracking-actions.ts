"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser } from "@/lib/server-auth";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function saveDriverAssignment(formData: FormData) {
  const truckId = String(formData.get("truck_id") ?? "");
  const driverId = String(formData.get("driver_user_id") ?? "");
  if (!uuidPattern.test(truckId) || !uuidPattern.test(driverId)) redirect("/dispatch/tracking?error=Choose%20a%20valid%20truck%20and%20SupplyOS%20user.");
  const { supabase, user } = await requireUser();
  const { data: membership } = await supabase.from("memberships").select("organization_id,role").eq("user_id", user.id).maybeSingle();
  if (!membership || !["owner", "admin", "manager", "dispatcher"].includes(membership.role)) redirect("/dispatch/tracking?error=You%20do%20not%20have%20permission%20to%20assign%20drivers.");
  const { data: driverMembership } = await supabase.from("memberships").select("user_id,role").eq("organization_id", membership.organization_id).eq("user_id", driverId).eq("role", "staff").maybeSingle();
  if (!driverMembership) redirect("/dispatch/tracking?error=The%20selected%20driver%20must%20be%20a%20staff%20member%20of%20this%20factory%20workspace.");
  const { data: truck } = await supabase.from("dispatch_trucks").select("id").eq("id", truckId).eq("organization_id", membership.organization_id).maybeSingle();
  if (!truck) redirect("/dispatch/tracking?error=Truck%20is%20not%20in%20your%20factory%20workspace.");
  const { error } = await supabase.from("dispatch_truck_driver_assignments").upsert({ organization_id: membership.organization_id, truck_id: truckId, driver_user_id: driverId, active: true, assigned_by: user.id, updated_at: new Date().toISOString() }, { onConflict: "truck_id" });
  if (error) redirect(`/dispatch/tracking?error=${encodeURIComponent(error.message)}`);
  revalidatePath("/dispatch/tracking");
  redirect("/dispatch/tracking?success=Driver%20assigned.%20The%20driver%20will%20see%20eligible%20in-transit%20loads%20after%20dispatch%20and%20truck-pass%20clearance.");
}

export async function deactivateDriverAssignment(formData: FormData) {
  const assignmentId = String(formData.get("assignment_id") ?? "");
  if (!uuidPattern.test(assignmentId)) redirect("/dispatch/tracking?error=Choose%20a%20valid%20assignment.");
  const { supabase, user } = await requireUser();
  const { data: membership } = await supabase.from("memberships").select("organization_id,role").eq("user_id", user.id).maybeSingle();
  if (!membership || !["owner", "admin", "manager", "dispatcher"].includes(membership.role)) redirect("/dispatch/tracking?error=You%20do%20not%20have%20permission%20to%20manage%20driver%20assignments.");
  const { error } = await supabase.from("dispatch_truck_driver_assignments").update({ active: false, updated_at: new Date().toISOString() }).eq("id", assignmentId).eq("organization_id", membership.organization_id);
  if (error) redirect(`/dispatch/tracking?error=${encodeURIComponent(error.message)}`);
  revalidatePath("/dispatch/tracking");
  redirect("/dispatch/tracking?success=Driver%20assignment%20deactivated.");
}
