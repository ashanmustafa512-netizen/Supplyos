"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser } from "@/lib/server-auth";

const messageUrl = (key: "success" | "error", value: string) => `/dispatch?${key}=${encodeURIComponent(value)}`;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function refreshDispatch() {
  revalidatePath("/dispatch");
  revalidatePath("/bookings");
  revalidatePath("/inventory");
  revalidatePath("/customers");
  revalidatePath("/dashboard");
}

export async function createDispatchPlan(formData: FormData) {
  const bookingIds = [...new Set(formData.getAll("booking_ids").map(String).filter(value => uuidPattern.test(value)))];
  const mode = String(formData.get("grouping_mode") ?? "city");
  const capacity = Number(formData.get("capacity_orders") ?? 10);
  const capacityKg = Number(formData.get("capacity_kg") ?? 0);
  const plannedDistanceKm = Number(formData.get("planned_distance_km") ?? 0);
  const plannedDeliveryDate = String(formData.get("planned_delivery_date") ?? "").trim();
  const modes = new Set(["route", "city", "province", "individual", "region", "district", "tehsil", "area", "zone"]);

  if (!bookingIds.length) redirect(messageUrl("error", "Select at least one approved booking to plan."));
  if (bookingIds.length > 250) redirect(messageUrl("error", "Plan no more than 250 bookings in a single run."));
  if (!modes.has(mode)) redirect(messageUrl("error", "Choose a valid load grouping strategy."));
  if (!Number.isInteger(capacity) || capacity < 1 || capacity > 1000) redirect(messageUrl("error", "Truck planning capacity must be a whole number between 1 and 1,000 orders."));
  if (!Number.isFinite(capacityKg) || capacityKg < 0 || !Number.isFinite(plannedDistanceKm) || plannedDistanceKm < 0) redirect(messageUrl("error", "Payload capacity and route distance must be non-negative numbers."));
  if (plannedDeliveryDate && !/^\d{4}-\d{2}-\d{2}$/.test(plannedDeliveryDate)) redirect(messageUrl("error", "Enter a valid planned delivery date."));

  const { supabase } = await requireUser();
  const { data, error } = await supabase.rpc("create_dispatch_plan_smart", {
    p_booking_ids: bookingIds,
    p_grouping_mode: mode,
    p_capacity_orders: capacity,
    p_capacity_kg: capacityKg,
    p_planned_distance_km: plannedDistanceKm,
    p_planned_delivery_date: plannedDeliveryDate || null,
  });
  if (error) redirect(messageUrl("error", error.message));
  refreshDispatch();
  const result = data as { load_count?: number; assigned_trucks?: number; booking_count?: number; consolidated_bookings?: number } | null;
  const loads = Number(result?.load_count ?? 0);
  const assigned = Number(result?.assigned_trucks ?? 0);
  const unassigned = Math.max(0, loads - assigned);
  const consolidated = Number(result?.consolidated_bookings ?? 0);
  const msg = `Planned ${bookingIds.length} bookings into ${loads} new load${loads === 1 ? "" : "s"}. ${consolidated} booking${consolidated === 1 ? "" : "s"} consolidated onto compatible existing routes${consolidated ? " before loading was sealed" : ""}. ${assigned} newly created truck assignment${assigned === 1 ? "" : "s"}${unassigned ? `; ${unassigned} load${unassigned === 1 ? " needs" : "s need"} a truck` : ""}.`;
  redirect(messageUrl("success", msg));
}

export async function createDispatchTruck(formData: FormData) {
  const registrationNo = String(formData.get("registration_no") ?? "").trim().toUpperCase();
  const displayName = String(formData.get("display_name") ?? "").trim();
  const capacityOrders = Number(formData.get("capacity_orders") ?? 0);
  const capacityKg = Number(formData.get("capacity_kg") ?? 0);
  const costPerKm = Number(formData.get("cost_per_km") ?? 0);
  const currentCity = String(formData.get("current_city") ?? "").trim();
  const driverName = String(formData.get("driver_name") ?? "").trim();
  const driverPhone = String(formData.get("driver_phone") ?? "").trim();

  if (!registrationNo || !displayName || !Number.isInteger(capacityOrders) || capacityOrders < 1 || capacityOrders > 1000 || !Number.isFinite(capacityKg) || capacityKg < 0 || !Number.isFinite(costPerKm) || costPerKm < 0) {
    redirect(messageUrl("error", "Enter a vehicle registration, name, valid order capacity, and non-negative capacity/cost values."));
  }

  const { supabase, user } = await requireUser();
  const { data: membership } = await supabase.from("memberships").select("organization_id").eq("user_id", user.id).maybeSingle();
  if (!membership) redirect(messageUrl("error", "No factory workspace is linked to this account."));
  const { error } = await supabase.from("dispatch_trucks").insert({
    organization_id: membership.organization_id,
    registration_no: registrationNo,
    display_name: displayName,
    capacity_orders: capacityOrders,
    capacity_kg: capacityKg,
    cost_per_km: costPerKm,
    current_city: currentCity,
    driver_name: driverName,
    driver_phone: driverPhone,
    // Let PostgreSQL apply the constrained default status. Direct INSERT privileges
    // intentionally do not let the browser claim a truck is already in transit.
  });
  if (error) redirect(messageUrl("error", error.code === "23505" ? "That registration number already exists in this workspace." : error.message));
  refreshDispatch();
  redirect(messageUrl("success", `Truck ${registrationNo} added to the fleet.`));
}

export async function updateDispatchTruck(formData: FormData) {
  const truckId = String(formData.get("truck_id") ?? "");
  const registrationNo = String(formData.get("registration_no") ?? "").trim().toUpperCase();
  const displayName = String(formData.get("display_name") ?? "").trim();
  const capacityOrders = Number(formData.get("capacity_orders"));
  const capacityKg = Number(formData.get("capacity_kg"));
  const costPerKm = Number(formData.get("cost_per_km"));
  const currentCity = String(formData.get("current_city") ?? "").trim().slice(0, 100);
  const driverName = String(formData.get("driver_name") ?? "").trim().slice(0, 120);
  const driverPhone = String(formData.get("driver_phone") ?? "").trim().slice(0, 40);
  const notes = String(formData.get("notes") ?? "").trim().slice(0, 500);

  if (!uuidPattern.test(truckId) || !registrationNo || !displayName || !Number.isInteger(capacityOrders) || capacityOrders < 1 || capacityOrders > 1000 || ![capacityKg, costPerKm].every(Number.isFinite) || capacityKg < 0 || costPerKm < 0) {
    redirect(messageUrl("error", "Enter a valid truck, registration, name, order capacity, payload, and running cost."));
  }

  const { supabase } = await requireUser();
  const { error } = await supabase.rpc("update_dispatch_truck_details", {
    p_truck_id: truckId,
    p_registration_no: registrationNo,
    p_display_name: displayName,
    p_capacity_orders: capacityOrders,
    p_capacity_kg: capacityKg,
    p_cost_per_km: costPerKm,
    p_current_city: currentCity,
    p_driver_name: driverName,
    p_driver_phone: driverPhone,
    p_notes: notes,
  });
  if (error) redirect(messageUrl("error", error.code === "23505" ? "That registration number already exists in this workspace." : error.message));
  refreshDispatch();
  redirect(messageUrl("success", `Vehicle ${registrationNo} details saved.`));
}

export async function updateDispatchTruckStatus(formData: FormData) {
  const truckId = String(formData.get("truck_id") ?? "");
  const status = String(formData.get("status") ?? "");
  if (!uuidPattern.test(truckId) || !["available", "maintenance", "inactive"].includes(status)) {
    redirect(messageUrl("error", "Invalid truck status change."));
  }
  const { supabase } = await requireUser();
  const { error } = await supabase.rpc("update_dispatch_truck_status", { p_truck_id: truckId, p_status: status });
  if (error) redirect(messageUrl("error", error.message));
  refreshDispatch();
  redirect(messageUrl("success", "Truck status updated."));
}

export async function assignDispatchTruck(formData: FormData) {
  const loadId = String(formData.get("load_id") ?? "");
  const truckId = String(formData.get("truck_id") ?? "").trim();
  if (!uuidPattern.test(loadId) || (truckId && !uuidPattern.test(truckId))) redirect(messageUrl("error", "Invalid load or truck selection."));
  const { supabase } = await requireUser();
  const { error } = await supabase.rpc("assign_dispatch_truck", { p_load_id: loadId, p_truck_id: truckId || null });
  if (error) redirect(messageUrl("error", error.message));
  refreshDispatch();
  redirect(messageUrl("success", truckId ? "Truck assigned to the load." : "Truck unassigned from the load."));
}

export async function dispatchLoadAction(formData: FormData) {
  const loadId = String(formData.get("load_id") ?? "");
  const action = String(formData.get("action") ?? "");
  if (!uuidPattern.test(loadId) || !["dispatch", "deliver", "cancel"].includes(action)) redirect(messageUrl("error", "Invalid load action."));
  const { supabase } = await requireUser();
  const { error } = await supabase.rpc("dispatch_load_action", { p_load_id: loadId, p_action: action });
  if (error) redirect(messageUrl("error", error.message));
  refreshDispatch();
  const labels: Record<string, string> = {
    dispatch: "Load departed. Its truck is now marked in transit.",
    deliver: "Load delivered. Each booking was completed and reserved stock was deducted transactionally.",
    cancel: "Planned load cancelled. Its bookings remain approved and can be planned again.",
  };
  redirect(messageUrl("success", labels[action]));
}

export async function createDispatchTarget(formData: FormData) {
  const name = String(formData.get("name") ?? "").trim();
  const periodType = String(formData.get("period_type") ?? "monthly");
  const startsOn = String(formData.get("starts_on") ?? "");
  const endsOn = String(formData.get("ends_on") ?? "");
  const targetDeliveries = Number(formData.get("target_deliveries") ?? 0);
  const targetLoads = Number(formData.get("target_loads") ?? 0);
  const targetOnTimeRate = Number(formData.get("target_on_time_rate") ?? 90);
  const notes = String(formData.get("notes") ?? "").trim().slice(0, 1000);
  if (!name || !["weekly", "monthly", "quarterly", "annual", "custom"].includes(periodType) || !/^\d{4}-\d{2}-\d{2}$/.test(startsOn) || !/^\d{4}-\d{2}-\d{2}$/.test(endsOn) || endsOn < startsOn || !Number.isInteger(targetDeliveries) || targetDeliveries < 0 || !Number.isInteger(targetLoads) || targetLoads < 0 || !Number.isFinite(targetOnTimeRate) || targetOnTimeRate < 0 || targetOnTimeRate > 100) {
    redirect(messageUrl("error", "Check the target name, date range, delivery/load numbers, and on-time percentage."));
  }
  const { supabase, user } = await requireUser();
  const { data: membership } = await supabase.from("memberships").select("organization_id").eq("user_id", user.id).maybeSingle();
  if (!membership) redirect(messageUrl("error", "No factory workspace is linked to this account."));
  const { error } = await supabase.from("dispatch_targets").insert({
    organization_id: membership.organization_id,
    name,
    period_type: periodType,
    starts_on: startsOn,
    ends_on: endsOn,
    target_deliveries: targetDeliveries,
    target_loads: targetLoads,
    target_on_time_rate: targetOnTimeRate,
    notes,
    created_by: user.id,
  });
  if (error) redirect(messageUrl("error", error.message));
  refreshDispatch();
  redirect(messageUrl("success", `Target “${name}” saved. SupplyOS will compare its pace with completed dispatches.`));
}

export async function updateCustomerDestination(formData: FormData) {
  const customerId = String(formData.get("customer_id") ?? "");
  if (!uuidPattern.test(customerId)) redirect(messageUrl("error", "Invalid customer."));
  const fields = ["city", "region", "province", "district", "tehsil", "area", "zone", "delivery_address"] as const;
  const update: Record<string, string | number | null> = {};
  for (const field of fields) update[field] = String(formData.get(field) ?? "").trim().slice(0, field === "delivery_address" ? 500 : 100);
  for (const field of ["latitude", "longitude"] as const) {
    const raw = String(formData.get(field) ?? "").trim();
    const value = raw === "" ? null : Number(raw);
    if (value !== null && (!Number.isFinite(value) || (field === "latitude" && (value < -90 || value > 90)) || (field === "longitude" && (value < -180 || value > 180)))) {
      redirect(messageUrl("error", `Enter a valid ${field === "latitude" ? "latitude from -90 to 90" : "longitude from -180 to 180"}, or leave it blank.`));
    }
    update[field] = value;
  }
  const { supabase } = await requireUser();
  const { error } = await supabase.from("customers").update(update).eq("id", customerId);
  if (error) redirect(messageUrl("error", error.message));
  refreshDispatch();
  redirect(messageUrl("success", "Customer destination profile saved. Open bookings inherit the address and coordinates for dispatch maps."));
}

export type DispatchCommandPayload = {
  load_id?: string;
  truck_id?: string | null;
  action?: string;
  load_ids?: string[];
  issue_type?: string;
  severity?: string;
  summary?: string;
  notes?: string;
  contingency_id?: string;
  action_taken?: string;
  latitude?: number;
  longitude?: number;
  accuracy_m?: number;
  recorded_at?: string;
  radius_m?: number;
  checklist?: Record<string, boolean>;
  loading_notes?: string;
  address?: string;
  inspection_notes?: string;
};

export type DispatchCommandResult = {
  ok: boolean;
  message: string;
  data?: Record<string, unknown> | null;
};

/**
 * In-place Dispatch mutations. Unlike the form/redirect actions above, this returns
 * structured feedback so the client can update a card without a full-page navigation.
 */
export async function runDispatchCommand(command: string, payload: DispatchCommandPayload): Promise<DispatchCommandResult> {
  try {
    const { supabase } = await requireUser();
    let data: Record<string, unknown> | null = null;
    let message = "Saved.";

    if (command === "assign_truck") {
      const loadId = String(payload.load_id ?? "");
      const truckId = String(payload.truck_id ?? "");
      if (!uuidPattern.test(loadId) || (truckId && !uuidPattern.test(truckId))) return { ok: false, message: "Choose a valid load and truck." };
      const { error } = await supabase.rpc("assign_dispatch_truck", { p_load_id: loadId, p_truck_id: truckId || null });
      if (error) return { ok: false, message: error.message };
      const { data: load } = await supabase.from("dispatch_loads").select("id, assigned_truck_id, estimated_cost, status").eq("id", loadId).maybeSingle();
      const { data: truckPass } = await supabase.from("dispatch_truck_passes").select("id, load_id, truck_id, pass_no, status, checklist, inspection_snapshot, inspection_notes, issued_at, checked_at").eq("load_id", loadId).maybeSingle();
      message = truckId ? "Truck assigned. Any prior vehicle inspection was invalidated for reinspection." : "Truck unassigned.";
      data = { ...(load as Record<string, unknown> | null ?? {}), truck_pass: truckPass };
    } else if (command === "complete_loading") {
      const loadId = String(payload.load_id ?? "");
      const checklist = payload.checklist as Record<string, boolean> | undefined;
      if (!uuidPattern.test(loadId) || !checklist) return { ok: false, message: "Complete the loading checklist." };
      const { error } = await supabase.rpc("finish_dispatch_loading", { p_load_id: loadId, p_checklist: checklist, p_loading_notes: String(payload.loading_notes ?? "") });
      if (error) return { ok: false, message: error.message };
      const { data: load } = await supabase.from("dispatch_loads").select("id, status, assigned_truck_id, loading_status, loading_started_at, loaded_at, loading_notes, loading_checklist, departed_at, delivered_at, estimated_cost").eq("id", loadId).maybeSingle();
      const { data: truckPass } = await supabase.from("dispatch_truck_passes").select("id, load_id, truck_id, pass_no, status, checklist, inspection_snapshot, inspection_notes, issued_at, checked_at").eq("load_id", loadId).maybeSingle();
      message = "Loading checklist completed. The truck pass was generated automatically and must be cleared before departure.";
      data = { ...(load as Record<string, unknown> | null ?? {}), truck_pass: truckPass };
    } else if (command === "load_action") {
      const loadId = String(payload.load_id ?? "");
      const action = String(payload.action ?? "");
      if (!uuidPattern.test(loadId) || !["start_loading", "finish_loading", "dispatch", "deliver", "cancel"].includes(action)) return { ok: false, message: "Invalid load action." };
      const { error } = await supabase.rpc("dispatch_load_action", { p_load_id: loadId, p_action: action });
      if (error) return { ok: false, message: error.message };
      const labels: Record<string, string> = {
        start_loading: "Loading started. Use the checklist to confirm the cargo is secured.",
        finish_loading: "Load marked ready to dispatch.",
        dispatch: "Truck dispatched successfully.",
        deliver: "Delivery confirmed. Orders and reserved stock were updated.",
        cancel: "Planned load cancelled. Approved bookings remain available for replanning.",
      };
      const { data: load } = await supabase.from("dispatch_loads").select("id, status, assigned_truck_id, loading_status, loading_started_at, loaded_at, loading_notes, loading_checklist, departed_at, delivered_at, estimated_cost").eq("id", loadId).maybeSingle();
      const { data: truckPass } = action === "finish_loading" ? await supabase.from("dispatch_truck_passes").select("id, load_id, truck_id, pass_no, status, checklist, inspection_snapshot, inspection_notes, issued_at, checked_at").eq("load_id", loadId).maybeSingle() : { data: null };
      message = action === "finish_loading" ? "Load marked ready. A truck inspection pass is generated automatically before departure." : labels[action];
      data = { ...(load as Record<string, unknown> | null ?? {}), truck_pass: truckPass };
    } else if (command === "bulk_dispatch") {
      const ids = [...new Set((payload.load_ids ?? []).filter(id => uuidPattern.test(id)))];
      if (!ids.length || ids.length !== (payload.load_ids ?? []).length || ids.length > 50) return { ok: false, message: "Select 1–50 valid ready loads." };
      const { data: result, error } = await supabase.rpc("bulk_dispatch_loads", { p_load_ids: ids });
      if (error) return { ok: false, message: error.message };
      message = `${Number((result as { dispatched_count?: number } | null)?.dispatched_count ?? ids.length)} loads dispatched. Their assigned trucks are now in transit.`;
      data = { load_ids: ids, ...(result as Record<string, unknown> ?? {}) };
    } else if (command === "report_contingency") {
      const loadId = String(payload.load_id ?? "");
      if (!uuidPattern.test(loadId)) return { ok: false, message: "Choose a valid load." };
      const { data: id, error } = await supabase.rpc("record_dispatch_contingency", {
        p_load_id: loadId,
        p_issue_type: String(payload.issue_type ?? "other"),
        p_severity: String(payload.severity ?? "medium"),
        p_summary: String(payload.summary ?? "").trim(),
        p_notes: String(payload.notes ?? "").trim(),
      });
      if (error) return { ok: false, message: error.message };
      const { data: record } = await supabase.from("dispatch_contingencies").select("id, load_id, issue_type, severity, summary, notes, status, created_at").eq("id", String(id)).maybeSingle();
      message = "Contingency reported and added to the dispatch incident log.";
      data = record as Record<string, unknown> | null;
    } else if (command === "resolve_contingency") {
      const id = String(payload.contingency_id ?? "");
      if (!uuidPattern.test(id)) return { ok: false, message: "Choose a valid contingency." };
      const { error } = await supabase.rpc("resolve_dispatch_contingency", { p_contingency_id: id, p_action_taken: String(payload.action_taken ?? "").trim() });
      if (error) return { ok: false, message: error.message };
      message = "Contingency resolved and resolution recorded.";
      data = { id, status: "resolved", action_taken: String(payload.action_taken ?? "").trim() };
    } else if (command === "issue_bill_pass") {
      const loadId = String(payload.load_id ?? "");
      if (!uuidPattern.test(loadId)) return { ok: false, message: "Choose a valid load." };
      const { data: id, error } = await supabase.rpc("issue_dispatch_bill_pass", { p_load_id: loadId });
      if (error) return { ok: false, message: error.message };
      const { data: pass, error: passError } = await supabase.from("dispatch_bill_passes").select("id, bill_pass_no, content_snapshot, issued_at").eq("id", String(id)).maybeSingle();
      if (passError || !pass) return { ok: false, message: passError?.message ?? "Pass issued but its snapshot could not be loaded." };
      message = "Driver bill pass generated. Review the details and print it.";
      data = pass as Record<string, unknown>;
    } else if (command === "update_location") {
      const truckId = String(payload.truck_id ?? "");
      const latitude = Number(payload.latitude); const longitude = Number(payload.longitude);
      if (!uuidPattern.test(truckId) || !Number.isFinite(latitude) || !Number.isFinite(longitude)) return { ok: false, message: "Enter valid truck coordinates." };
      const { data: result, error } = await supabase.rpc("set_dispatch_truck_location", { p_truck_id: truckId, p_latitude: latitude, p_longitude: longitude });
      if (error) return { ok: false, message: error.message };
      const { data: activeLoads } = await supabase.from("dispatch_loads").select("id").eq("assigned_truck_id", truckId).eq("status", "in_transit");
      const { data: truckPosition } = await supabase.from("dispatch_trucks").select("id,current_latitude,current_longitude,location_updated_at,factory_distance_m,factory_geofence_state,factory_geofence_checked_at").eq("id", truckId).maybeSingle();
      const activeLoadIds = (activeLoads ?? []).map(load => load.id);
      const { data: states } = activeLoadIds.length ? await supabase.from("dispatch_geofence_states").select("load_id, booking_id, state, distance_m, radius_m, last_checked_at").in("load_id", activeLoadIds) : { data: [] as Array<Record<string, unknown>> };
      message = `Location saved. ${Number((result as { geofence_transitions?: number } | null)?.geofence_transitions ?? 0)} geofence transition(s) detected.`;
      data = { truck_id: truckId, latitude, longitude, ...(result as Record<string, unknown> ?? {}), truck_position: truckPosition, geofence_states: states ?? [] };
    } else if (command === "update_gps_location") {
      const truckId = String(payload.truck_id ?? "");
      const latitude = Number(payload.latitude);
      const longitude = Number(payload.longitude);
      const accuracyM = Number(payload.accuracy_m);
      const recordedAt = String(payload.recorded_at ?? "");
      const recordedAtMs = Date.parse(recordedAt);
      if (!uuidPattern.test(truckId) || !Number.isFinite(latitude) || latitude < -90 || latitude > 90 || !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
        return { ok: false, message: "The device reported invalid GPS coordinates." };
      }
      if (!Number.isFinite(accuracyM) || accuracyM < 0 || accuracyM > 10000) {
        return { ok: false, message: "The device did not return a valid GPS accuracy value. Wait for a fresh GPS fix and retry." };
      }
      if (!Number.isFinite(recordedAtMs) || recordedAtMs > Date.now() + 30000 || recordedAtMs < Date.now() - 30 * 1000) {
        return { ok: false, message: "That GPS fix is older than 30 seconds. Wait for a fresh device location and try again." };
      }
      const { data: result, error } = await supabase.rpc("set_dispatch_truck_gps_location", {
        p_truck_id: truckId, p_latitude: latitude, p_longitude: longitude,
        p_accuracy_m: accuracyM, p_recorded_at: new Date(recordedAtMs).toISOString(),
      });
      if (error) return { ok: false, message: error.message };
      const { data: activeLoads } = await supabase.from("dispatch_loads").select("id").eq("assigned_truck_id", truckId).eq("status", "in_transit");
      const { data: truckPosition } = await supabase.from("dispatch_trucks")
        .select("id,current_latitude,current_longitude,location_updated_at,factory_distance_m,factory_geofence_state,factory_geofence_checked_at,location_source,current_location_accuracy_m")
        .eq("id", truckId).maybeSingle();
      const activeLoadIds = (activeLoads ?? []).map(load => load.id);
      const { data: states } = activeLoadIds.length
        ? await supabase.from("dispatch_geofence_states").select("load_id, booking_id, state, distance_m, radius_m, last_checked_at").in("load_id", activeLoadIds)
        : { data: [] as Array<Record<string, unknown>> };
      const transitionCount = Number((result as { geofence_transitions?: number } | null)?.geofence_transitions ?? 0);
      message = accuracyM <= 150
        ? `GPS saved (${Math.round(accuracyM)} m accuracy). ${transitionCount} delivery geofence transition(s) detected.`
        : `GPS coordinates saved (${Math.round(accuracyM)} m accuracy), but the fix is too imprecise to confirm arrival. Geofence status remains unknown until a fix at 150 m accuracy or better.`;
      data = { truck_id: truckId, latitude, longitude, ...(result as Record<string, unknown> ?? {}), truck_position: truckPosition, geofence_states: states ?? [] };
    } else if (command === "set_geofence_radius") {
      const loadId = String(payload.load_id ?? ""); const radius = Number(payload.radius_m);
      if (!uuidPattern.test(loadId) || !Number.isInteger(radius)) return { ok: false, message: "Choose a load and a whole-number geofence radius." };
      const { error } = await supabase.rpc("set_dispatch_geofence_radius", { p_load_id: loadId, p_radius_m: radius });
      if (error) return { ok: false, message: error.message };
      message = `Delivery geofence updated to ${radius} metres.`;
      data = { load_id: loadId, radius_m: radius };
    } else if (command === "set_factory_geofence") {
      const latitude = Number(payload.latitude); const longitude = Number(payload.longitude); const radius = Number(payload.radius_m);
      if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90 || !Number.isFinite(longitude) || longitude < -180 || longitude > 180 || !Number.isInteger(radius)) {
        return { ok: false, message: "Enter valid factory coordinates and a whole-number radius." };
      }
      if (radius < 25 || radius > 10000) return { ok: false, message: "Factory radius must be between 25 and 10,000 metres." };
      const { data: result, error } = await supabase.rpc("set_dispatch_factory_geofence", {
        p_latitude: latitude, p_longitude: longitude, p_address: String(payload.address ?? "").trim().slice(0, 300), p_radius_m: radius,
      });
      if (error) return { ok: false, message: `Factory geofence was not saved: ${error.message}` };
      const saved = result as Record<string, unknown> | null;
      if (!saved || saved.factory_latitude == null || saved.factory_longitude == null || saved.factory_geofence_radius_m == null) {
        return { ok: false, message: "The database did not confirm the saved factory coordinates. Apply the latest SupplyOS geofence migration, then try again." };
      }
      revalidatePath("/routes");
      revalidatePath("/dispatch");
      revalidatePath("/dashboard");
      message = `Factory geofence saved and verified at ${Number(saved.factory_latitude).toFixed(6)}, ${Number(saved.factory_longitude).toFixed(6)} with a ${Number(saved.factory_geofence_radius_m)} m radius. Fleet distances were recalculated.`;
      data = saved;
    } else if (command === "complete_truck_pass") {
      const loadId = String(payload.load_id ?? "");
      const checklist = payload.checklist as Record<string, boolean> | undefined;
      if (!uuidPattern.test(loadId) || !checklist) return { ok: false, message: "Submit the truck inspection checklist." };
      const { data: result, error } = await supabase.rpc("complete_dispatch_truck_pass", {
        p_load_id: loadId, p_checklist: checklist, p_inspection_notes: String(payload.inspection_notes ?? "").trim().slice(0, 2000),
      });
      if (error) return { ok: false, message: error.message };
      const { data: pass, error: passError } = await supabase.from("dispatch_truck_passes")
        .select("id, load_id, truck_id, pass_no, status, checklist, inspection_snapshot, inspection_notes, issued_at, checked_at")
        .eq("load_id", loadId).maybeSingle();
      if (passError || !pass) return { ok: false, message: passError?.message ?? "Inspection was saved but its pass could not be reloaded." };
      message = String((result as { status?: string } | null)?.status ?? "hold") === "cleared"
        ? "Truck inspection passed. Dispatch is now enabled for this vehicle."
        : "Truck pass placed on HOLD. Resolve every failed or incomplete check before dispatch.";
      data = pass as unknown as Record<string, unknown>;
    } else {
      return { ok: false, message: "Unsupported dispatch action." };
    }

    // Do not revalidate/refresh the current route here. These protected pages query
    // Supabase on navigation; the active client updates its state from this result.
    return { ok: true, message, data };
  } catch (error) {
    return { ok: false, message: error instanceof Error ? error.message : "The operation failed. Please try again." };
  }
}
