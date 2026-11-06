import type { Metadata } from "next";
import { requireUser } from "@/lib/server-auth";
import { DispatchConsole, type DispatchBooking, type DispatchLoad, type DispatchTarget, type DispatchTruck, type DestinationCustomer, type InventoryItem, type DispatchContingency, type TruckPass } from "@/components/dispatch-console";

export const metadata: Metadata = { title: "Dispatch & fleet" };
type SearchParams = Promise<{ success?: string; error?: string; tab?: string }>;

function pakistanDate() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Karachi", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
}

export default async function DispatchPage({ searchParams }: { searchParams: SearchParams }) {
  const params = await searchParams;
  const { supabase, user } = await requireUser();
  const [bookingResult, loadResult, truckResult, targetResult, productResult, customerResult, contingencyResult, truckPassResult] = await Promise.all([
    supabase.from("bookings").select("id, booking_no, booking_date, city, region, province, district, tehsil, area, zone, delivery_address, latitude, longitude, status, total_amount, total_cost, booking_items(quantity, products(name, sku, unit_weight_kg)), customers(name, customer_code, city, region)").eq("status", "approved").order("booking_date", { ascending: true }).order("booking_no").limit(1000),
    supabase.from("dispatch_loads").select("id, load_no, grouping_mode, group_key, destination_summary, stop_plan, booking_count, capacity_orders, estimated_weight_kg, assigned_truck_id, status, planned_delivery_date, planned_distance_km, estimated_cost, notes, departed_at, delivered_at, created_at, loading_status, loading_started_at, loaded_at, loading_notes, loading_checklist, geofence_radius_m, dispatch_trucks(id, registration_no, display_name, capacity_orders, capacity_kg, cost_per_km, current_city, driver_name, driver_phone, status, current_latitude, current_longitude, location_updated_at), dispatch_load_bookings(id, booking_id, stop_order, delivery_status, delivered_at, bookings(id, booking_no, city, region, province, district, tehsil, area, zone, delivery_address, latitude, longitude, total_amount, customers(name, customer_code, phone)))").order("stop_order", { referencedTable: "dispatch_load_bookings", ascending: true }).order("created_at", { ascending: false }).limit(500),
    supabase.from("dispatch_trucks").select("id, registration_no, display_name, capacity_orders, capacity_kg, cost_per_km, current_city, driver_name, driver_phone, status, current_latitude, current_longitude, location_updated_at, notes, created_at").order("created_at", { ascending: false }).limit(250),
    supabase.from("dispatch_targets").select("id, name, period_type, starts_on, ends_on, target_deliveries, target_loads, target_on_time_rate, is_active, notes, created_at").eq("is_active", true).order("starts_on", { ascending: false }).limit(100),
    supabase.from("products").select("id, sku, name, unit, stock_on_hand, stock_reserved, unit_weight_kg, is_active").eq("is_active", true).order("name").limit(500),
    supabase.from("customers").select("id, customer_code, name, city, region, province, district, tehsil, area, zone, delivery_address, latitude, longitude, phone").eq("status", "active").order("name").limit(500),
    supabase.from("dispatch_contingencies").select("id, load_id, issue_type, severity, summary, notes, status, action_taken, created_at, dispatch_loads(load_no)").order("created_at", { ascending: false }).limit(200),
    supabase.from("dispatch_truck_passes").select("id, load_id, truck_id, pass_no, status, checklist, inspection_snapshot, inspection_notes, issued_at, checked_at").order("issued_at", { ascending: false }).limit(500),
  ]);

  const bookings = (bookingResult.data ?? []) as unknown as DispatchBooking[];
  const loads = (loadResult.data ?? []) as unknown as DispatchLoad[];
  const trucks = (truckResult.data ?? []) as unknown as DispatchTruck[];
  const targets = (targetResult.data ?? []) as unknown as DispatchTarget[];
  const products = (productResult.data ?? []) as unknown as InventoryItem[];
  const customers = (customerResult.data ?? []) as unknown as DestinationCustomer[];
  const contingencies = (contingencyResult.data ?? []) as unknown as DispatchContingency[];
  const truckPasses = (truckPassResult.data ?? []) as unknown as TruckPass[];
  const databaseError = [bookingResult.error, loadResult.error, truckResult.error, targetResult.error, productResult.error, customerResult.error, contingencyResult.error, truckPassResult.error].find(Boolean)?.message;

  const assignedIds = new Set<string>();
  for (const load of loads) {
    if (load.status === "cancelled") continue;
    for (const item of load.dispatch_load_bookings ?? []) if (item.booking_id) assignedIds.add(item.booking_id);
  }
  const unplannedBookings = bookings.filter(booking => !assignedIds.has(booking.id));
  const today = pakistanDate();
  const unassignedLoads = loads.filter(load => ["planned", "ready"].includes(load.status) && !load.assigned_truck_id);
  const overdueLoads = loads.filter(load => load.planned_delivery_date && load.planned_delivery_date < today && !["delivered", "cancelled"].includes(load.status));
  const maintenanceTrucks = trucks.filter(truck => truck.status === "maintenance");
  const stockRisk = products.filter(product => Number(product.stock_reserved) > 0 && (Number(product.stock_on_hand) <= 0 || Number(product.stock_reserved) / Number(product.stock_on_hand) >= 0.85));
  const behindTargets = targets.filter(target => {
    if (today < target.starts_on || today > target.ends_on || Number(target.target_deliveries) <= 0) return false;
    const periodLoads = loads.filter(load => load.status === "delivered" && load.delivered_at && load.delivered_at.slice(0, 10) >= target.starts_on && load.delivered_at.slice(0, 10) <= today);
    const actual = periodLoads.reduce((sum, load) => sum + Number(load.booking_count), 0);
    const totalDays = Math.max(1, Math.floor((new Date(`${target.ends_on}T12:00:00`).getTime() - new Date(`${target.starts_on}T12:00:00`).getTime()) / 86400000) + 1);
    const elapsedDays = Math.max(1, Math.floor((new Date(`${today}T12:00:00`).getTime() - new Date(`${target.starts_on}T12:00:00`).getTime()) / 86400000) + 1);
    return (actual / elapsedDays * totalDays) < Number(target.target_deliveries);
  });
  const warnings = [
    ...(unplannedBookings.length ? [{ id: "backlog", severity: "warning" as const, title: `${unplannedBookings.length} approved booking${unplannedBookings.length === 1 ? " is" : "s are"} not planned`, detail: "These orders have approval and inventory reservations but are not attached to a dispatch load.", tab: "loads" as const }] : []),
    ...(unassignedLoads.length ? [{ id: "truckless", severity: "critical" as const, title: `${unassignedLoads.length} planned load${unassignedLoads.length === 1 ? " has" : "s have"} no truck`, detail: "Assign an available truck with enough order capacity before departure.", tab: "loads" as const }] : []),
    ...(overdueLoads.length ? [{ id: "overdue", severity: "critical" as const, title: `${overdueLoads.length} load${overdueLoads.length === 1 ? " is" : "s are"} past the planned delivery date`, detail: "Review the route status and update the expected delivery date if the plan changed.", tab: "loads" as const }] : []),
    ...(maintenanceTrucks.length ? [{ id: "maintenance", severity: "warning" as const, title: `${maintenanceTrucks.length} truck${maintenanceTrucks.length === 1 ? " is" : "s are"} in maintenance`, detail: "These vehicles are excluded from auto-assignment until marked available.", tab: "trucks" as const }] : []),
    ...(stockRisk.length ? [{ id: "stock-risk", severity: "warning" as const, title: `${stockRisk.length} SKU${stockRisk.length === 1 ? " has" : "s have"} at least 85% of stock reserved`, detail: stockRisk.slice(0, 4).map(p => p.name).join(", ") + (stockRisk.length > 4 ? ", and more" : ""), tab: "loads" as const }] : []),
    ...(behindTargets.length ? [{ id: "target-pace", severity: "warning" as const, title: `${behindTargets.length} dispatch target${behindTargets.length === 1 ? " is" : "s are"} behind the current pace`, detail: behindTargets.slice(0, 3).map(target => target.name).join(", ") + (behindTargets.length > 3 ? ", and more" : "") + ". Review staffing, load size, and route consolidation.", tab: "targets" as const }] : []),
    ...(!targets.length ? [{ id: "no-target", severity: "info" as const, title: "No active dispatch targets", detail: "Add a weekly or monthly target to make on-pace and behind-pace forecasts visible.", tab: "targets" as const }] : []),
  ];

  return <DispatchConsole
    success={params.success}
    error={params.error}
    databaseError={databaseError}
    initialTab={params.tab}
    bookings={unplannedBookings}
    allApprovedCount={bookings.length}
    loads={loads}
    trucks={trucks}
    targets={targets}
    customers={customers}
    products={products}
    warnings={warnings}
    contingencies={contingencies}
    truckPasses={truckPasses}
    today={today}
    userId={user.id}
  />;
}
