"use client";

import { Fragment, useMemo, useState } from "react";
import {
  Activity, AlertOctagon, AlertTriangle, ArrowRight,
  Boxes, Check, CheckCircle2, ChevronDown, Download, Gauge,
  MapPin, PackageCheck, Plus, Route, Search, ShieldAlert, Target, Truck, Users,
  Wallet, Wrench, Printer, X, Navigation,
} from "lucide-react";
import {
  createDispatchPlan, createDispatchTarget, createDispatchTruck,
  updateCustomerDestination, updateDispatchTruck, updateDispatchTruckStatus, runDispatchCommand,
} from "@/app/(app)/dispatch/actions";
import { compactNumber, dateLabel, money } from "@/lib/format";

type Relation<T> = T | T[] | null | undefined;
const related = <T,>(value: Relation<T>): T | null => Array.isArray(value) ? value[0] ?? null : (value ?? null) as T | null;

export type DispatchBooking = {
  id: string; booking_no: string; booking_date: string; city: string; region: string; province: string; district: string;
  tehsil: string; area: string; zone: string; delivery_address: string; latitude: number | null; longitude: number | null;
  status: string; total_amount: number | string; total_cost: number | string;
  customers?: Relation<{ name: string; customer_code: string; city: string; region: string }>;
  booking_items?: { quantity: number | string; products?: Relation<{ name: string; sku: string; unit_weight_kg: number | string }> }[];
};
export type DispatchTruck = {
  id: string; registration_no: string; display_name: string; capacity_orders: number; capacity_kg: number | string;
  cost_per_km: number | string; current_city: string; driver_name: string; driver_phone: string; status: string;
  notes?: string; created_at?: string; current_latitude?: number | string | null; current_longitude?: number | string | null; location_updated_at?: string | null;
};
export type StopPlan = { stop_order: number; city: string; region: string; province: string; district: string; tehsil: string; area: string; zone: string; booking_count: number };
export type DispatchLoad = {
  id: string; load_no: string; grouping_mode: string; group_key: string; destination_summary: string; stop_plan: StopPlan[];
  booking_count: number; capacity_orders: number; estimated_weight_kg: number | string; assigned_truck_id: string | null; status: string; planned_delivery_date: string | null;
  planned_distance_km: number | string; estimated_cost: number | string; notes: string; departed_at: string | null; delivered_at: string | null;
  loading_status?: "not_started" | "loading" | "loaded"; loading_started_at?: string | null; loaded_at?: string | null; loading_notes?: string; loading_checklist?: Record<string, boolean>; geofence_radius_m?: number;
  created_at: string; dispatch_trucks?: Relation<DispatchTruck>;
  dispatch_load_bookings?: { id: string; booking_id: string; stop_order: number; delivery_status: string; delivered_at: string | null; bookings?: Relation<{ id: string; booking_no: string; city: string; region: string; province: string; district?: string; tehsil?: string; area?: string; zone?: string; delivery_address?: string; latitude?: number | null; longitude?: number | null; total_amount: number | string; customers?: Relation<{ name: string; customer_code: string; phone?: string }> }> }[];
};
export type DispatchTarget = { id: string; name: string; period_type: string; starts_on: string; ends_on: string; target_deliveries: number; target_loads: number; target_on_time_rate: number | string; is_active: boolean; notes: string; created_at: string };
export type DestinationCustomer = { id: string; customer_code: string; name: string; city: string; region: string; province: string; district: string; tehsil: string; area: string; zone: string; delivery_address: string; latitude?: number | string | null; longitude?: number | string | null; phone?: string };
export type InventoryItem = { id: string; sku: string; name: string; unit: string; stock_on_hand: number | string; stock_reserved: number | string; unit_weight_kg: number | string; is_active: boolean };
export type DispatchContingency = { id: string; load_id: string; issue_type: string; severity: string; summary: string; notes?: string; status: string; action_taken?: string; created_at: string; dispatch_loads?: Relation<{ load_no: string }> };
type BillPass = { id: string; bill_pass_no: string; issued_at: string; content_snapshot: { load: Record<string, unknown>; truck: Record<string, unknown>; orders: Array<Record<string, unknown>>; notice: string } };
export type TruckPass = { id: string; load_id: string; truck_id: string; pass_no: string; status: "inspection_pending" | "cleared" | "hold"; checklist: Record<string, boolean>; inspection_snapshot: Record<string, unknown>; inspection_notes: string; issued_at: string; checked_at: string | null };
const TRUCK_PASS_DEFAULT: Record<string, boolean> = { tyres_checked: false, brakes_checked: false, lights_checked: false, mirrors_checked: false, horn_reverse_checked: false, fire_extinguisher_checked: false, documents_checked: false, cargo_secured: false };
const TRUCK_PASS_CHECKS: { key: string; label: string; detail: string }[] = [
  { key: "tyres_checked", label: "Tyres, wheel nuts and visible leaks checked", detail: "Inspect tyre condition/pressure, wheel nuts and fluid leaks." },
  { key: "brakes_checked", label: "Service brake and parking brake tested", detail: "Do not clear the vehicle if braking is weak or abnormal." },
  { key: "lights_checked", label: "Headlights, indicators and brake lights working", detail: "Confirm required exterior lights work before gate release." },
  { key: "mirrors_checked", label: "Mirrors, windscreen and visibility checked", detail: "Confirm driver visibility is not obstructed." },
  { key: "horn_reverse_checked", label: "Horn and reversing alarm checked", detail: "Confirm warning devices operate where fitted." },
  { key: "fire_extinguisher_checked", label: "Fire extinguisher and safety equipment present", detail: "Check presence, access and visible inspection status." },
  { key: "documents_checked", label: "Driver, vehicle and dispatch documents checked", detail: "Verify required documents against factory policy and local law." },
  { key: "cargo_secured", label: "Cargo secured; weight/capacity and seal verified", detail: "Check restraints and that the cargo matches the load record." },
];
type Warning = { id: string; severity: "critical" | "warning" | "info"; title: string; detail: string; tab: "loads" | "targets" | "trucks" };
type Tab = "loads" | "targets" | "warnings" | "reports" | "trucks" | "destinations" | "incidents";

const GROUPING_MODES: { value: string; label: string; description: string }[] = [
  { value: "route", label: "Route / multi-city", description: "Combine cities into multi-stop loads; destination order is a planning draft, not map-optimized." },
  { value: "city", label: "City", description: "Keep each load within one city." },
  { value: "province", label: "Province", description: "Consolidate orders by province." },
  { value: "region", label: "Region", description: "Consolidate orders by region." },
  { value: "district", label: "District", description: "Consolidate orders by district." },
  { value: "tehsil", label: "Tehsil", description: "Consolidate orders by tehsil." },
  { value: "area", label: "Area", description: "Consolidate orders by area." },
  { value: "zone", label: "Zone", description: "Consolidate orders by zone." },
  { value: "individual", label: "Individual delivery", description: "Create a separate load for every order." },
];
const TAB_ITEMS: { value: Tab; label: string; icon: typeof Truck }[] = [
  { value: "loads", label: "Load board", icon: Route },
  { value: "trucks", label: "Trucks", icon: Truck },
  { value: "targets", label: "Targets", icon: Target },
  { value: "warnings", label: "Early warning", icon: ShieldAlert },
  { value: "incidents", label: "Contingencies", icon: AlertOctagon },
  { value: "reports", label: "Reports", icon: Activity },
  { value: "destinations", label: "Destinations", icon: MapPin },
];

function locationLabel(booking: DispatchBooking) {
  const destination = related(booking.customers);
  return [booking.city || destination?.city, booking.region || destination?.region, booking.province, booking.district].filter(Boolean).join(", ") || "Destination not set";
}
function estimatedBookingWeight(booking: DispatchBooking) {
  return (booking.booking_items ?? []).reduce((sum, item) => sum + Number(item.quantity) * Number(related(item.products)?.unit_weight_kg ?? 0), 0);
}
function monthEndIso(date: string) {
  const [year, month] = date.split("-").map(Number);
  return `${year}-${String(month).padStart(2, "0")}-${String(new Date(year, month, 0).getDate()).padStart(2, "0")}`;
}
function groupingKey(booking: DispatchBooking, mode: string) {
  if (mode === "individual") return booking.id;
  if (mode === "route") return "Consolidated multi-city route";
  if (mode === "province") return booking.province || "Province not set";
  if (mode === "region") return booking.region || "Region not set";
  if (mode === "district") return booking.district || "District not set";
  if (mode === "tehsil") return booking.tehsil || "Tehsil not set";
  if (mode === "area") return booking.area || "Area not set";
  if (mode === "zone") return booking.zone || "Zone not set";
  return booking.city || "Unknown city";
}
function loadStatusClass(status: string) {
  if (status === "delivered") return "dispatch-status dispatch-status-delivered";
  if (status === "in_transit") return "dispatch-status dispatch-status-transit";
  if (status === "cancelled") return "dispatch-status dispatch-status-cancelled";
  return "dispatch-status dispatch-status-planned";
}
function isOpenLoad(load: DispatchLoad) { return !["delivered", "cancelled"].includes(load.status); }

export function DispatchConsole(props: {
  success?: string; error?: string; databaseError?: string; initialTab?: string;
  bookings: DispatchBooking[]; allApprovedCount: number; loads: DispatchLoad[]; trucks: DispatchTruck[];
  targets: DispatchTarget[]; customers: DestinationCustomer[]; products: InventoryItem[]; warnings: Warning[]; contingencies: DispatchContingency[]; truckPasses: TruckPass[]; today: string; userId: string;
}) {
  const [activeTab, setActiveTab] = useState<Tab>(["loads", "targets", "warnings", "reports", "trucks", "destinations", "incidents"].includes(props.initialTab ?? "") ? props.initialTab as Tab : "loads");
  const [liveLoads, setLiveLoads] = useState<DispatchLoad[]>(props.loads);
  const [liveTrucks, setLiveTrucks] = useState<DispatchTruck[]>(props.trucks);
  const [liveContingencies, setLiveContingencies] = useState<DispatchContingency[]>(props.contingencies);
  const [liveTruckPasses, setLiveTruckPasses] = useState<TruckPass[]>(props.truckPasses);
  const [selectedDispatchLoadIds, setSelectedDispatchLoadIds] = useState<string[]>([]);
  const [truckSelection, setTruckSelection] = useState<Record<string, string>>({});
  const [commandBusy, setCommandBusy] = useState<string | null>(null);
  const [commandNotice, setCommandNotice] = useState<{ ok: boolean; message: string } | null>(null);
  const [contingencyLoadId, setContingencyLoadId] = useState<string | null>(null);
  const [resolveContingencyId, setResolveContingencyId] = useState<string | null>(null);
  const [resolutionText, setResolutionText] = useState("");
  const [billPass, setBillPass] = useState<BillPass | null>(null);
  const [truckPassLoadId, setTruckPassLoadId] = useState<string | null>(null);
  const [truckPassChecklist, setTruckPassChecklist] = useState<Record<string, boolean>>(TRUCK_PASS_DEFAULT);
  const [truckPassNotes, setTruckPassNotes] = useState("");
  const [loadingLoadId, setLoadingLoadId] = useState<string | null>(null);
  const [loadingNotes, setLoadingNotes] = useState("");
  const [loadingChecklist, setLoadingChecklist] = useState({ quantities_verified: false, packages_checked: false, cargo_secured: false, documents_ready: false });
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [groupingMode, setGroupingMode] = useState("city");
  const [capacityOrders, setCapacityOrders] = useState("10");
  const [capacityKg, setCapacityKg] = useState("0");
  const [plannedDistanceKm, setPlannedDistanceKm] = useState("0");
  const [deliveryDate, setDeliveryDate] = useState("");
  const [bookingSearch, setBookingSearch] = useState("");
  const [bookingLocationFilter, setBookingLocationFilter] = useState("all");
  const [loadSearch, setLoadSearch] = useState("");
  const [loadStatusFilter, setLoadStatusFilter] = useState("all");
  const [customerSearch, setCustomerSearch] = useState("");
  const [contingencyType, setContingencyType] = useState("breakdown");
  const [contingencySeverity, setContingencySeverity] = useState("high");
  const [contingencySummary, setContingencySummary] = useState("");
  const [contingencyNotes, setContingencyNotes] = useState("");

  const availableBookings = useMemo(() => props.bookings.filter(booking => {
    const customer = related(booking.customers);
    const query = bookingSearch.trim().toLowerCase();
    const matchesSearch = !query || [booking.booking_no, customer?.name, customer?.customer_code, booking.city, booking.region, booking.province, booking.district].some(v => String(v ?? "").toLowerCase().includes(query));
    const location = booking.city || customer?.city || "";
    return matchesSearch && (bookingLocationFilter === "all" || location === bookingLocationFilter);
  }), [props.bookings, bookingSearch, bookingLocationFilter]);
  const selectedBookings = useMemo(() => props.bookings.filter(booking => selectedIds.includes(booking.id)), [props.bookings, selectedIds]);
  const selectedLoadsEstimate = useMemo(() => {
    const groups = new Map<string, number[]>();
    for (const booking of selectedBookings) {
      const key = groupingKey(booking, groupingMode);
      groups.set(key, [...(groups.get(key) ?? []), estimatedBookingWeight(booking)]);
    }
    const capacity = Math.max(1, Number(capacityOrders) || 10);
    const maxKg = Math.max(0, Number(capacityKg) || 0);
    let loads = 0;
    let overweight = 0;
    for (const weights of groups.values()) {
      let orders = 0; let weight = 0;
      for (const nextWeight of weights) {
        if (maxKg > 0 && nextWeight > maxKg) overweight += 1;
        if (orders >= capacity || (maxKg > 0 && orders > 0 && weight + nextWeight > maxKg)) { loads += 1; orders = 0; weight = 0; }
        orders += 1; weight += nextWeight;
      }
      if (orders > 0) loads += 1;
    }
    const cities = new Set(selectedBookings.map(booking => booking.city).filter(Boolean));
    return { loads, groups: groups.size, cities: cities.size, capacity, overweight };
  }, [selectedBookings, groupingMode, capacityOrders, capacityKg]);

  const filteredLoads = useMemo(() => liveLoads.filter(load => {
    const query = loadSearch.trim().toLowerCase();
    const matchesSearch = !query || [load.load_no, load.destination_summary, load.group_key, related(load.dispatch_trucks)?.registration_no].some(value => String(value ?? "").toLowerCase().includes(query));
    return matchesSearch && (loadStatusFilter === "all" || load.status === loadStatusFilter);
  }), [liveLoads, loadSearch, loadStatusFilter]);
  const currentTruckIds = useMemo(() => new Set(liveLoads.filter(isOpenLoad).map(load => load.assigned_truck_id).filter(Boolean) as string[]), [liveLoads]);
  const availableTrucks = useMemo(() => liveTrucks.filter(truck => truck.status === "available"), [liveTrucks]);
  const inTransitLoads = useMemo(() => liveLoads.filter(load => load.status === "in_transit"), [liveLoads]);
  const deliveredLoads = useMemo(() => liveLoads.filter(load => load.status === "delivered"), [liveLoads]);
  const todayDelivered = useMemo(() => deliveredLoads.filter(load => load.delivered_at?.slice(0, 10) === props.today), [deliveredLoads, props.today]);
  const totalInTransitOrders = useMemo(() => inTransitLoads.reduce((sum, load) => sum + Number(load.booking_count), 0), [inTransitLoads]);
  const deliveredOrders = useMemo(() => deliveredLoads.reduce((sum, load) => sum + Number(load.booking_count), 0), [deliveredLoads]);
  const estimatedSpend = useMemo(() => liveLoads.filter(load => ["delivered", "in_transit"].includes(load.status)).reduce((sum, load) => sum + Number(load.estimated_cost ?? 0), 0), [liveLoads]);
  const averageUtilization = useMemo(() => {
    const eligibleLoads = liveLoads.filter(load => load.status !== "cancelled" && load.capacity_orders > 0);
    if (!eligibleLoads.length) return 0;
    const utilization = eligibleLoads.reduce((sum, load) => sum + Number(load.booking_count) / Number(load.capacity_orders), 0);
    return Math.round(utilization / eligibleLoads.length * 100);
  }, [liveLoads]);
  const highReservationProducts = useMemo(() => props.products.filter(product => Number(product.stock_on_hand) > 0 && Number(product.stock_reserved) / Number(product.stock_on_hand) >= 0.85), [props.products]);
  const clearedTruckPassKeys = useMemo(() => new Set(liveTruckPasses
    .filter(pass => pass.status === "cleared")
    .map(pass => `${pass.load_id}:${pass.truck_id}`)), [liveTruckPasses]);
  const dispatchReadyLoads = useMemo(() => liveLoads.filter(load =>
    load.status === "ready" && load.loading_status === "loaded" && !!load.assigned_truck_id
      && clearedTruckPassKeys.has(`${load.id}:${load.assigned_truck_id}`)
  ), [liveLoads, clearedTruckPassKeys]);
  const locations = useMemo(() => [...new Set(props.bookings.map(booking => booking.city).filter(Boolean))].sort(), [props.bookings]);
  const modeDescription = GROUPING_MODES.find(mode => mode.value === groupingMode)?.description ?? "";
  const activeTruckPass = useMemo(() => truckPassLoadId ? liveTruckPasses.find(pass => pass.load_id === truckPassLoadId) ?? null : null, [liveTruckPasses, truckPassLoadId]);
  const activeTruckPassSnapshot = activeTruckPass?.inspection_snapshot ?? {};
  const activeTruckPassLoadSnapshot = (activeTruckPassSnapshot.load as Record<string, unknown> | undefined) ?? {};
  const activeTruckPassTruckSnapshot = (activeTruckPassSnapshot.truck as Record<string, unknown> | undefined) ?? {};
  const activeTruckPassFactorySnapshot = (activeTruckPassSnapshot.factory as Record<string, unknown> | undefined) ?? {};

  function toggleBooking(id: string, checked: boolean) {
    setSelectedIds(current => checked ? (current.includes(id) ? current : current.length < 250 ? [...current, id] : current) : current.filter(value => value !== id));
  }
  function chooseVisible(checked: boolean) {
    setSelectedIds(current => {
      if (!checked) return current.filter(id => !availableBookings.some(booking => booking.id === id));
      const combined = [...new Set([...current, ...availableBookings.map(booking => booking.id)])];
      return combined.slice(0, 250);
    });
  }
  async function runCommand(command: string, payload: Parameters<typeof runDispatchCommand>[1], busyKey: string) {
    setCommandBusy(busyKey); setCommandNotice(null);
    const result = await runDispatchCommand(command, payload);
    setCommandBusy(null); setCommandNotice({ ok: result.ok, message: result.message });
    if (!result.ok) {
      if (command === "assign_truck") {
        const loadId = String(payload.load_id ?? "");
        setTruckSelection(current => ({ ...current, [loadId]: liveLoads.find(load => load.id === loadId)?.assigned_truck_id ?? "" }));
      }
      return;
    }
    const data = result.data ?? {};
    const now = new Date().toISOString();
    if (command === "assign_truck") {
      const loadId = String(payload.load_id ?? ""); const truckId = String(payload.truck_id ?? "");
      const returned = data as { assigned_truck_id?: string | null; estimated_cost?: number | string; truck_pass?: TruckPass | null };
      if (returned.truck_pass) setLiveTruckPasses(current => current.some(pass => pass.id === returned.truck_pass!.id) ? current.map(pass => pass.id === returned.truck_pass!.id ? returned.truck_pass! : pass) : [returned.truck_pass!, ...current]);
      setLiveLoads(current => current.map(load => load.id === loadId ? { ...load, assigned_truck_id: returned.assigned_truck_id ?? (truckId || null), estimated_cost: returned.estimated_cost ?? load.estimated_cost, dispatch_trucks: liveTrucks.find(truck => truck.id === (returned.assigned_truck_id ?? truckId)) ?? null } : load));
      setTruckSelection(current => ({ ...current, [loadId]: returned.assigned_truck_id ?? truckId }));
      setSelectedDispatchLoadIds(current => current.filter(id => id !== loadId));
    } else if (command === "load_action" || command === "complete_loading") {
      const loadId = String(payload.load_id ?? ""); const action = command === "complete_loading" ? "finish_loading" : String(payload.action ?? "");
      const updated = data as Partial<DispatchLoad> & { truck_pass?: TruckPass | null };
      const before = liveLoads.find(load => load.id === loadId);
      setLiveLoads(current => current.map(load => load.id === loadId ? { ...load, ...updated, id: load.id, departed_at: updated.departed_at ?? (action === "dispatch" ? now : load.departed_at), delivered_at: updated.delivered_at ?? (action === "deliver" ? now : load.delivered_at), loading_notes: command === "complete_loading" ? String(payload.loading_notes ?? "") : load.loading_notes, loading_checklist: command === "complete_loading" ? payload.checklist as Record<string, boolean> : load.loading_checklist } : load));
      if (updated.truck_pass) setLiveTruckPasses(current => current.some(pass => pass.id === updated.truck_pass?.id)
        ? current.map(pass => pass.id === updated.truck_pass?.id ? updated.truck_pass! : pass)
        : [updated.truck_pass!, ...current]);
      if (command === "complete_loading") { setLoadingLoadId(null); setLoadingNotes(""); setLoadingChecklist({ quantities_verified: false, packages_checked: false, cargo_secured: false, documents_ready: false }); }
      const truckId = before?.assigned_truck_id;
      if (truckId && action === "dispatch") setLiveTrucks(current => current.map(truck => truck.id === truckId ? { ...truck, status: "in_transit" } : truck));
      if (truckId && action === "deliver") setLiveTrucks(current => current.map(truck => truck.id === truckId ? { ...truck, status: "available", current_city: before?.stop_plan?.at(-1)?.city || truck.current_city } : truck));
      if (action === "cancel" && truckId) setLiveLoads(current => current.map(load => load.id === loadId ? { ...load, assigned_truck_id: null, dispatch_trucks: null } : load));
      if (["dispatch", "cancel", "deliver"].includes(action)) setSelectedDispatchLoadIds(current => current.filter(id => id !== loadId));
    } else if (command === "bulk_dispatch") {
      const ids = (payload.load_ids ?? []) as string[];
      const selectedLoads = liveLoads.filter(load => ids.includes(load.id));
      const truckIds = new Set(selectedLoads.map(load => load.assigned_truck_id).filter(Boolean));
      setLiveLoads(current => current.map(load => ids.includes(load.id) ? { ...load, status: "in_transit", departed_at: now } : load));
      setLiveTrucks(current => current.map(truck => truckIds.has(truck.id) ? { ...truck, status: "in_transit" } : truck));
      setSelectedDispatchLoadIds([]);
    } else if (command === "report_contingency") {
      setLiveContingencies(current => [data as unknown as DispatchContingency, ...current]); setContingencyLoadId(null); setContingencySummary(""); setContingencyNotes("");
    } else if (command === "resolve_contingency") {
      setLiveContingencies(current => current.map(item => item.id === String(payload.contingency_id) ? { ...item, status: "resolved", action_taken: String(payload.action_taken ?? "") } : item));
      setResolveContingencyId(null); setResolutionText("");
    } else if (command === "issue_bill_pass") {
      setBillPass(data as unknown as BillPass);
    } else if (command === "complete_truck_pass") {
      const updatedPass = data as unknown as TruckPass;
      setLiveTruckPasses(current => current.some(pass => pass.id === updatedPass.id)
        ? current.map(pass => pass.id === updatedPass.id ? { ...pass, ...updatedPass } : pass)
        : [updatedPass, ...current]);
    } else if (command === "set_geofence_radius") {
      setLiveLoads(current => current.map(load => load.id === String(payload.load_id) ? { ...load, geofence_radius_m: Number(payload.radius_m) } : load));
    }
  }

  function toggleDispatchLoad(id: string, checked: boolean) {
    setSelectedDispatchLoadIds(current => checked ? [...new Set([...current, id])] : current.filter(value => value !== id));
  }

  function exportCsv() {
    const rows = [["Load", "Status", "Grouping", "Destinations", "Orders", "Capacity", "Estimated weight kg", "Truck", "Planned date", "Distance km", "Estimated cost", "Departed at", "Delivered at"]];
    for (const load of liveLoads) rows.push([load.load_no, load.status, load.grouping_mode, load.destination_summary, String(load.booking_count), String(load.capacity_orders), String(load.estimated_weight_kg ?? 0), related(load.dispatch_trucks)?.registration_no ?? "Unassigned", load.planned_delivery_date ?? "", String(load.planned_distance_km ?? 0), String(load.estimated_cost ?? 0), load.departed_at ?? "", load.delivered_at ?? ""]);
    const csv = rows.map(row => row.map(value => `"${String(value).replaceAll('"', '""')}"`).join(",")).join("\r\n");
    const blob = new Blob(["\ufeff", csv], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a"); anchor.href = url; anchor.download = `supplyos-dispatch-report-${props.today}.csv`; anchor.click(); URL.revokeObjectURL(url);
  }

  return <div className="page-stack dispatch-page">
    <div className="page-heading-row"><div><div className="eyebrow">OPERATIONS / LOGISTICS CONTROL</div><h1>Dispatch <span className="heading-count">{liveLoads.length} loads</span></h1><p>Combine approved orders into practical loads, reserve the right stock, and control the fleet through delivery.</p></div><div className="heading-actions"><button type="button" className="button button-secondary" onClick={exportCsv}><Download size={16}/> Export report</button></div></div>
    {props.success && <div className="notice notice-success"><CheckCircle2 size={16}/>{props.success}</div>}
    {props.error && <div className="notice notice-error"><AlertTriangle size={16}/>{props.error}</div>}
    {props.databaseError && <div className="notice notice-error"><AlertOctagon size={16}/> Dispatch data could not fully load: {props.databaseError}. Confirm the Dispatch migration has been applied to the same Supabase project used by this app.</div>}
    {commandNotice && <div className={`dispatch-inline-status ${commandNotice.ok ? "success" : "error"}`}><span>{commandNotice.ok ? <CheckCircle2 size={16}/> : <AlertTriangle size={16}/>}</span><span>{commandNotice.message}</span><button type="button" className="icon-button" aria-label="Dismiss message" onClick={() => setCommandNotice(null)}><X size={15}/></button></div>}

    <div className="dispatch-metric-grid">
      <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-blue"><PackageCheck size={17}/></span><span className="metric-trend">Ready to plan</span></div><div className="metric-value">{props.bookings.length}</div><div className="metric-label">Approved bookings without a load</div><div className="metric-subtext">From {props.allApprovedCount} approved orders</div></div>
      <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-amber"><Truck size={17}/></span><span className="metric-trend">Live movement</span></div><div className="metric-value">{inTransitLoads.length}</div><div className="metric-label">Loads in transit</div><div className="metric-subtext">{totalInTransitOrders} orders currently moving</div></div>
      <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-green"><CheckCircle2 size={17}/></span><span className="metric-trend">Today</span></div><div className="metric-value">{todayDelivered.reduce((sum, load) => sum + Number(load.booking_count), 0)}</div><div className="metric-label">Orders delivered today</div><div className="metric-subtext">{todayDelivered.length} completed loads</div></div>
      <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-violet"><Gauge size={17}/></span><span className="metric-trend">Fleet efficiency</span></div><div className="metric-value">{averageUtilization}<span className="metric-suffix">%</span></div><div className="metric-label">Average load utilization</div><div className="metric-subtext">Orders used vs. planning capacity</div></div>
    </div>

    <div className="dispatch-tabs" role="tablist" aria-label="Dispatch tools">{TAB_ITEMS.map(tab => { const Icon = tab.icon; const count = tab.value === "warnings" ? props.warnings.length : tab.value === "incidents" ? liveContingencies.filter(item => item.status === "open").length : tab.value === "trucks" ? liveTrucks.length : tab.value === "loads" ? liveLoads.length : null; return <button key={tab.value} type="button" role="tab" aria-selected={activeTab === tab.value} className={`dispatch-tab ${activeTab === tab.value ? "dispatch-tab-active" : ""}`} onClick={() => setActiveTab(tab.value)}><Icon size={15}/><span>{tab.label}</span>{count !== null && <small>{count}</small>}</button>; })}</div>

    {activeTab === "loads" && <div className="page-stack dispatch-tab-panel">
      <section className="panel dispatch-planner-panel">
        <div className="panel-heading"><div><h2>Load planning board</h2><p>Select approved orders, choose a consolidation rule, and estimate how many truckloads are needed before creating the plan.</p></div><span className="panel-heading-icon"><Route size={17}/></span></div>
        <div className="dispatch-planner-controls">
          <label className="field-label">Consolidation strategy<select value={groupingMode} onChange={event => setGroupingMode(event.target.value)}>{GROUPING_MODES.map(mode => <option key={mode.value} value={mode.value}>{mode.label}</option>)}</select><span className="field-hint dispatch-mode-description">{modeDescription}</span></label>
          <label className="field-label">Planning capacity <span className="field-hint">orders / load</span><select value={capacityOrders} onChange={event => setCapacityOrders(event.target.value)}>{[...new Set([5, 10, 15, 20, 25, 30, ...liveTrucks.map(truck => Number(truck.capacity_orders))])].filter(value => Number.isInteger(value) && value > 0).sort((a,b) => a-b).map(value => <option key={value} value={String(value)}>{value} orders</option>)}</select></label>
          <label className="field-label">Payload cap <span className="field-hint">kg / load · optional</span><select value={capacityKg} onChange={event => setCapacityKg(event.target.value)}>{[...new Set([0, ...liveTrucks.map(truck => Number(truck.capacity_kg)).filter(value => Number.isFinite(value) && value > 0)])].sort((a,b) => a-b).map(value => <option key={value} value={String(value)}>{value === 0 ? "Not set / ignore weight" : `${compactNumber(value)} kg`}</option>)}</select></label>
          <label className="field-label">Route distance <span className="field-hint">km per load</span><input type="number" min="0" step="0.1" value={plannedDistanceKm} onChange={event => setPlannedDistanceKm(event.target.value)}/><span className="field-hint">Optional cost estimate input</span></label>
          <label className="field-label">Planned delivery date<input type="date" value={deliveryDate} min={props.today} onChange={event => setDeliveryDate(event.target.value)}/><span className="field-hint">Optional scheduling marker</span></label>
          <div className="dispatch-plan-estimate"><div><span>Estimated truckloads</span><strong>{selectedIds.length ? selectedLoadsEstimate.loads : "—"}</strong></div><div><span>Selected orders</span><strong>{selectedIds.length}</strong></div><div><span>Destination groups</span><strong>{selectedIds.length ? selectedLoadsEstimate.groups : "—"}</strong></div></div>
        </div>
        <div className="dispatch-estimate-note"><Activity size={15}/><span>Estimate uses the chosen order capacity. Route mode can combine multiple cities into one load; when coordinates and a routing provider are not configured, stops are listed in a consistent draft order rather than claimed as the cheapest/fastest route.</span></div>
        <div className="dispatch-stock-note"><Boxes size={16}/><div><strong>Stock reservation check is active</strong><span>Booking approval already reserves stock. Plan creation rechecks that the selected orders are covered by reservations; delivery confirmation consumes the reserved stock.</span></div><span className="stock-note-count">{highReservationProducts.length ? `${highReservationProducts.length} high-reserve SKUs` : "No high-reserve alert"}</span></div>
        <div className="dispatch-booking-toolbar"><label className="search-field"><Search size={15}/><input value={bookingSearch} onChange={event => setBookingSearch(event.target.value)} placeholder="Search booking, customer, destination…"/></label><label className="booking-filter">City<select value={bookingLocationFilter} onChange={event => setBookingLocationFilter(event.target.value)}><option value="all">All cities</option>{locations.map(location => <option value={location} key={location}>{location}</option>)}</select></label><span className="dispatch-selection-count">{selectedIds.length} selected <button type="button" onClick={() => setSelectedIds([])} disabled={!selectedIds.length}>Clear</button></span></div>
        <form action={createDispatchPlan}>
          <input type="hidden" name="grouping_mode" value={groupingMode}/><input type="hidden" name="capacity_orders" value={capacityOrders}/><input type="hidden" name="capacity_kg" value={capacityKg}/><input type="hidden" name="planned_distance_km" value={plannedDistanceKm}/><input type="hidden" name="planned_delivery_date" value={deliveryDate}/>
          {selectedIds.map(id => <input key={id} type="hidden" name="booking_ids" value={id}/>)}
          <div className="table-scroll"><table className="data-table dispatch-bookings-table"><thead><tr><th className="dispatch-select-col"><input aria-label="Select all visible approved bookings" type="checkbox" checked={availableBookings.length > 0 && availableBookings.every(booking => selectedIds.includes(booking.id))} onChange={event => chooseVisible(event.target.checked)}/></th><th>Booking</th><th>Customer</th><th>Destination</th><th>Order value</th><th>Items / weight</th><th>Stock status</th></tr></thead><tbody>
            {availableBookings.map(booking => {
              const customer = related(booking.customers);
              const itemSummary = (booking.booking_items ?? []).map(item => { const product = related(item.products); return `${product?.name ?? "Item"} × ${compactNumber(item.quantity)}`; }).join(", ");
              const estimatedWeight = (booking.booking_items ?? []).reduce((sum, item) => sum + Number(item.quantity) * Number(related(item.products)?.unit_weight_kg ?? 0), 0);
              const selected = selectedIds.includes(booking.id);
              return <tr key={booking.id} className={selected ? "dispatch-row-selected" : ""}><td className="dispatch-select-col"><input type="checkbox" aria-label={`Select ${booking.booking_no}`} checked={selected} onChange={event => toggleBooking(booking.id, event.target.checked)}/></td><td><strong className="table-primary-text">{booking.booking_no}</strong><small className="table-muted">{dateLabel(booking.booking_date)}</small></td><td><strong>{customer?.name ?? "Customer"}</strong><small className="table-muted">{customer?.customer_code ?? ""}</small></td><td><strong>{locationLabel(booking)}</strong><small className="table-muted">{booking.zone || booking.area || booking.delivery_address || "Set destination levels for more precise planning"}</small></td><td><strong>{money(Number(booking.total_amount))}</strong></td><td><span className="dispatch-item-summary">{itemSummary || "Order items"}</span><small className="table-muted">{estimatedWeight > 0 ? `${compactNumber(estimatedWeight)} kg est.` : "Weight not configured"}</small></td><td><span className="dispatch-stock-ready"><CheckCircle2 size={13}/> Reserved on approval</span><small className="table-muted">Final recheck during planning</small></td></tr>;
            })}
            {!availableBookings.length && <tr><td colSpan={7}><div className="empty-table"><div className="empty-table-icon"><PackageCheck size={20}/></div><strong>No approved bookings waiting for dispatch</strong><p>Approve bookings first, then they will appear here until assigned to a load.</p><a className="button button-secondary button-small" href="/bookings">Review bookings <ArrowRight size={14}/></a></div></td></tr>}
          </tbody></table></div>
          <div className="dispatch-planner-footer"><div><strong>{selectedIds.length} booking{selectedIds.length === 1 ? "" : "s"} selected</strong><span>{selectedIds.length ? `Estimated ${selectedLoadsEstimate.loads} load${selectedLoadsEstimate.loads === 1 ? "" : "s"} at ${selectedLoadsEstimate.capacity} orders per load${Number(capacityKg) > 0 ? ` / ${compactNumber(Number(capacityKg))} kg max` : ""}.` : "Select orders to preview and create a load plan."}{selectedLoadsEstimate.overweight > 0 ? ` ${selectedLoadsEstimate.overweight} selected order(s) exceed the payload cap; planning will stop and explain which booking needs more capacity.` : ""}</span></div><button className="button button-primary" type="submit" disabled={!selectedIds.length || selectedLoadsEstimate.overweight > 0}><Route size={16}/> Create load plan <ArrowRight size={15}/></button></div>
        </form>
      </section>

      <section className="panel"><div className="panel-heading"><div><h2>Dispatch & loading board</h2><p>Assign a truck, start loading, verify cargo, then dispatch one load or a ready batch.</p></div><div className="dispatch-load-toolbar"><label className="search-field"><Search size={14}/><input value={loadSearch} onChange={event => setLoadSearch(event.target.value)} placeholder="Find load, destination or truck"/></label><select aria-label="Filter load status" value={loadStatusFilter} onChange={event => setLoadStatusFilter(event.target.value)}><option value="all">All statuses</option><option value="planned">Planned</option><option value="ready">Ready</option><option value="in_transit">In transit</option><option value="delivered">Delivered</option><option value="cancelled">Cancelled</option></select></div></div>
        <div className="dispatch-load-toolbar-actions"><label className="dispatch-load-heading-select"><input className="dispatch-load-checkbox" type="checkbox" aria-label="Select all ready loads for bulk dispatch" checked={dispatchReadyLoads.length > 0 && dispatchReadyLoads.every(load => selectedDispatchLoadIds.includes(load.id))} onChange={event => setSelectedDispatchLoadIds(event.target.checked ? dispatchReadyLoads.map(load => load.id) : [])}/><span>Select inspected & ready ({dispatchReadyLoads.length})</span></label><div className="dispatch-load-action-row"><button type="button" className="button button-secondary button-small" onClick={() => setSelectedDispatchLoadIds(dispatchReadyLoads.map(load => load.id))} disabled={!dispatchReadyLoads.length}>Select inspected loads</button><button type="button" className="button button-primary button-small" onClick={() => void runCommand("bulk_dispatch", { load_ids: selectedDispatchLoadIds }, "bulk-dispatch")} disabled={!selectedDispatchLoadIds.length || commandBusy === "bulk-dispatch"}><ArrowRight size={14}/>{commandBusy === "bulk-dispatch" ? "Dispatching…" : `Dispatch selected (${selectedDispatchLoadIds.length})`}</button></div></div>
        <div className="dispatch-load-list">{filteredLoads.map(load => {
          const truck = related(load.dispatch_trucks) ?? liveTrucks.find(candidate => candidate.id === load.assigned_truck_id) ?? null;
          const loadItems = load.dispatch_load_bookings ?? [];
          const assignableTrucks = liveTrucks.filter(candidate => candidate.status === "available" && candidate.capacity_orders >= load.booking_count && (Number(candidate.capacity_kg) === 0 || Number(candidate.capacity_kg) >= Number(load.estimated_weight_kg ?? 0)) && (!currentTruckIds.has(candidate.id) || candidate.id === load.assigned_truck_id));
          const stops = Array.isArray(load.stop_plan) ? load.stop_plan : [];
          const truckPass = liveTruckPasses.find(pass => pass.load_id === load.id) ?? null;
          const truckPassCleared = !!truckPass && truckPass.status === "cleared" && truckPass.truck_id === load.assigned_truck_id;
          const canBulkDispatch = load.status === "ready" && load.loading_status === "loaded" && !!load.assigned_truck_id && truckPassCleared;
          const busyKey = `load:${load.id}`;
          return <article className="dispatch-load-card" key={load.id}>
            <div className="dispatch-load-top"><div className="dispatch-load-id">{canBulkDispatch && <input className="dispatch-load-checkbox" type="checkbox" aria-label={`Select ${load.load_no} for bulk dispatch`} checked={selectedDispatchLoadIds.includes(load.id)} onChange={event => toggleDispatchLoad(load.id, event.target.checked)}/>}<span className="dispatch-load-icon"><Truck size={18}/></span><div><strong>{load.load_no}</strong><span>{GROUPING_MODES.find(mode => mode.value === load.grouping_mode)?.label ?? load.grouping_mode} · created {dateLabel(load.created_at)}</span></div></div><span className={loadStatusClass(load.status)}>{load.status.replace("_", " ")}</span></div>
            <div className="dispatch-load-main"><div className="dispatch-load-dest"><span className="dispatch-detail-label">DESTINATION / STOP PLAN</span><strong>{load.destination_summary || "Destination pending"}</strong><div className="dispatch-stop-chips">{stops.slice(0, 5).map(stop => <span key={`${stop.stop_order}-${stop.city}`}><i>{stop.stop_order}</i>{stop.city}{stop.booking_count > 1 ? ` · ${stop.booking_count} orders` : ""}</span>)}{stops.length > 5 && <span>+{stops.length - 5} stops</span>}</div></div><div className="dispatch-load-facts"><div><span>Orders</span><strong>{load.booking_count}</strong></div><div><span>Capacity</span><strong>{load.capacity_orders}</strong></div><div><span>Est. weight</span><strong>{Number(load.estimated_weight_kg ?? 0) > 0 ? `${compactNumber(load.estimated_weight_kg)} kg` : "—"}</strong></div><div><span>Utilization</span><strong>{load.capacity_orders ? Math.round(load.booking_count / load.capacity_orders * 100) : 0}%</strong></div><div><span>Planned date</span><strong>{load.planned_delivery_date ? dateLabel(load.planned_delivery_date) : "Not set"}</strong></div></div></div>
            <div className="dispatch-loading-track"><span className={`dispatch-step ${load.loading_status && load.loading_status !== "not_started" ? "done" : "current"}`}>1 · Loading</span><span className={`dispatch-step ${load.loading_status === "loaded" ? "done" : load.loading_status === "loading" ? "current" : ""}`}>2 · Cargo verified</span><span className={`dispatch-step ${load.status === "ready" || load.status === "in_transit" || load.status === "delivered" ? "done" : ""}`}>3 · Ready</span><span className={`dispatch-step ${load.status === "in_transit" || load.status === "delivered" ? "done" : ""}`}>4 · Dispatched</span><span className={`dispatch-step ${load.status === "delivered" ? "done" : ""}`}>5 · Delivered</span></div>
            <div className="dispatch-load-bottom"><div className="dispatch-truck-summary"><span className={`truck-mini-icon ${truck ? "" : "truck-mini-unassigned"}`}><Truck size={15}/></span><div><strong>{truck ? `${truck.registration_no} · ${truck.display_name}` : "Truck not assigned"}</strong><small>{truck ? `${truck.capacity_orders} orders capacity${truck.driver_name ? ` · ${truck.driver_name}` : ""}` : "Select a truck that fits this load."}</small></div></div>
              <div className="dispatch-load-actions">
                {(["planned", "ready"].includes(load.status)) && <label className="dispatch-truck-chooser"><span className="sr-only">Assign truck to {load.load_no}</span><select aria-label={`Assign truck to ${load.load_no}`} value={truckSelection[load.id] ?? load.assigned_truck_id ?? ""} disabled={commandBusy === busyKey} onChange={event => { const value = event.target.value; setTruckSelection(current => ({ ...current, [load.id]: value })); void runCommand("assign_truck", { load_id: load.id, truck_id: value || null }, busyKey); }}><option value="">{load.assigned_truck_id ? "Unassign truck…" : "Select truck…"}</option>{assignableTrucks.map(candidate => <option key={candidate.id} value={candidate.id}>{candidate.registration_no} · {candidate.display_name} ({candidate.capacity_orders})</option>)}{truck && !assignableTrucks.some(candidate => candidate.id === truck.id) && <option value={truck.id}>{truck.registration_no} · currently assigned</option>}</select>{commandBusy === busyKey && <span className="dispatch-spinner"/>}</label>}
                {load.status === "planned" && load.loading_status !== "loading" && <button type="button" className="button button-primary button-small" disabled={!load.assigned_truck_id || commandBusy === busyKey} onClick={() => void runCommand("load_action", { load_id: load.id, action: "start_loading" }, busyKey)}><Boxes size={14}/>{load.loading_status === "loaded" ? "Loading complete" : "Start loading"}</button>}
                {load.status === "planned" && load.loading_status === "loading" && <button type="button" className="button button-primary button-small" disabled={!load.assigned_truck_id || commandBusy === busyKey} onClick={() => { setLoadingLoadId(load.id); setLoadingNotes(load.loading_notes ?? ""); setLoadingChecklist({ quantities_verified: false, packages_checked: false, cargo_secured: false, documents_ready: false }); }}><CheckCircle2 size={14}/> Complete loading checklist</button>}
                {load.status === "ready" && <button type="button" className="button button-primary button-small" disabled={!truckPassCleared || commandBusy === busyKey} onClick={() => void runCommand("load_action", { load_id: load.id, action: "dispatch" }, busyKey)}><Navigation size={14}/>{commandBusy === busyKey ? "Dispatching…" : truckPassCleared ? "Dispatch now" : "Inspection required"}</button>}
                {(["ready", "in_transit"].includes(load.status)) && <button type="button" className={`button ${truckPassCleared ? "button-secondary" : "button-primary"} button-small`} onClick={() => {
                  if (!truckPass) { setCommandNotice({ ok: false, message: "Truck pass is missing. Refresh Dispatch after confirming the latest database migration." }); return; }
                  setTruckPassLoadId(load.id); setTruckPassChecklist({ ...TRUCK_PASS_DEFAULT, ...truckPass.checklist }); setTruckPassNotes(truckPass.inspection_notes ?? "");
                }}><Printer size={14}/>{truckPass ? `Truck pass · ${truckPass.status === "cleared" ? "cleared" : truckPass.status === "hold" ? "HOLD" : "check"}` : "Truck pass missing"}</button>}
                {(["ready", "in_transit"].includes(load.status)) && <button type="button" className="button button-secondary button-small" disabled={commandBusy === `pass:${load.id}`} onClick={() => void runCommand("issue_bill_pass", { load_id: load.id }, `pass:${load.id}`)}><Printer size={14}/>{commandBusy === `pass:${load.id}` ? "Preparing…" : "Bill pass"}</button>}
                {load.status === "in_transit" && <button type="button" className="button button-primary button-small" disabled={commandBusy === busyKey} onClick={() => void runCommand("load_action", { load_id: load.id, action: "deliver" }, busyKey)}><Check size={14}/>{commandBusy === busyKey ? "Confirming…" : "Confirm delivered"}</button>}
                {(["planned", "ready", "in_transit"].includes(load.status)) && <button type="button" className="button button-secondary button-small" onClick={() => setContingencyLoadId(load.id)}><AlertOctagon size={14}/> Report issue</button>}
                {(["planned", "ready"].includes(load.status)) && <button type="button" className="button button-ghost button-small" disabled={commandBusy === busyKey} onClick={() => { if (window.confirm(`Cancel ${load.load_no}? Its approved bookings will remain available for replanning.`)) void runCommand("load_action", { load_id: load.id, action: "cancel" }, busyKey); }}>Cancel</button>}
                {load.status === "delivered" && <div className="dispatch-completed-label"><CheckCircle2 size={15}/> Delivered {load.delivered_at ? new Date(load.delivered_at).toLocaleString("en-PK", { dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Karachi" }) : ""}</div>}
                {load.status === "cancelled" && <span className="muted">Load cancelled · bookings can be replanned</span>}
              </div>
            </div>
            {load.notes && <p className="dispatch-load-notes">{load.notes}</p>}
            <details className="dispatch-load-details"><summary>View {loadItems.length} shop / booking stops <ChevronDown size={14}/></summary><div className="dispatch-booking-pills">{loadItems.map(item => { const booking = related(item.bookings); const customer = related(booking?.customers); return <span key={item.id}><strong>{booking?.booking_no ?? item.booking_id.slice(0, 8)}</strong><small>{customer?.name ?? booking?.city ?? "Customer"}</small><small>{[booking?.delivery_address, booking?.city, booking?.province].filter(Boolean).join(", ") || "Address not set"}</small>{customer?.phone && <small>{customer.phone}</small>}</span>; })}{!loadItems.length && <span>No booking links loaded.</span>}</div><div className="dispatch-load-detail-actions"><a className="button button-secondary button-small" href="/routes"><MapPin size={13}/> View routes & addresses</a></div></details>
          </article>;
        })}{!filteredLoads.length && <div className="empty-table"><div className="empty-table-icon"><Truck size={20}/></div><strong>No loads match this view</strong><p>Create a load plan above, or change the filters.</p></div>}</div>
      </section>
    </div>}

    {activeTab === "trucks" && <div className="page-stack dispatch-tab-panel">
      <div className="dispatch-two-column"><section className="panel"><div className="panel-heading"><div><h2>Fleet directory</h2><p>Vehicles are auto-assigned only when available and large enough for the planned load.</p></div><span className="table-count">{liveTrucks.length} vehicles</span></div><div className="table-scroll"><table className="data-table"><thead><tr><th>Truck / registration</th><th>Capacity</th><th>Driver / base</th><th>Cost / km</th><th>Status</th><th>Availability</th></tr></thead><tbody>{liveTrucks.map(truck => { const reserved = currentTruckIds.has(truck.id); return <Fragment key={truck.id}><tr><td><div className="dispatch-truck-directory"><span className="dispatch-load-icon"><Truck size={17}/></span><span><strong>{truck.registration_no}</strong><small>{truck.display_name}</small></span></div></td><td><strong>{truck.capacity_orders} orders</strong><small className="table-muted">{Number(truck.capacity_kg) > 0 ? `${compactNumber(truck.capacity_kg)} kg` : "Weight capacity not set"}</small></td><td><strong>{truck.driver_name || "Driver not set"}</strong><small className="table-muted">{truck.current_city || "Base city not set"}{truck.driver_phone ? ` · ${truck.driver_phone}` : ""}</small></td><td>{money(Number(truck.cost_per_km))}</td><td><span className={`dispatch-status ${truck.status === "available" ? "dispatch-status-delivered" : truck.status === "in_transit" ? "dispatch-status-transit" : "dispatch-status-cancelled"}`}>{truck.status.replace("_", " ")}</span></td><td>{truck.status === "in_transit" ? <span className="muted">On trip</span> : <form action={updateDispatchTruckStatus} className="dispatch-truck-status-form"><input type="hidden" name="truck_id" value={truck.id}/><select name="status" aria-label={`Set status for ${truck.registration_no}`} defaultValue={truck.status}><option value="available">Available</option><option value="maintenance">Maintenance</option><option value="inactive">Inactive</option></select><button className="button button-xs button-secondary" type="submit">Save</button>{reserved && <small className="table-muted">Reserved by a planned load</small>}</form>}</td></tr><tr className="dispatch-truck-edit-row"><td colSpan={6}><details className="dispatch-truck-edit"><summary>Edit vehicle, capacity, running cost, and driver details</summary><form action={updateDispatchTruck} className="dispatch-truck-edit-form"><input type="hidden" name="truck_id" value={truck.id}/><label>Registration<input name="registration_no" defaultValue={truck.registration_no} maxLength={32} required/></label><label>Vehicle name/type<input name="display_name" defaultValue={truck.display_name} maxLength={100} required/></label><label>Order capacity<input name="capacity_orders" type="number" min="1" max="1000" defaultValue={truck.capacity_orders} required/></label><label>Payload kg<input name="capacity_kg" type="number" min="0" step="0.01" defaultValue={truck.capacity_kg} required/></label><label>Cost per km (PKR)<input name="cost_per_km" type="number" min="0" step="0.01" defaultValue={truck.cost_per_km} required/></label><label>Current/base city<input name="current_city" defaultValue={truck.current_city} maxLength={100}/></label><label>Driver name<input name="driver_name" defaultValue={truck.driver_name} maxLength={120}/></label><label>Driver phone<input name="driver_phone" defaultValue={truck.driver_phone} maxLength={40}/></label><label className="dispatch-truck-edit-notes">Fleet notes<input name="notes" defaultValue={truck.notes ?? ""} maxLength={500}/></label><button className="button button-secondary button-small" type="submit">Save vehicle details</button></form></details></td></tr></Fragment>; })}{!liveTrucks.length && <tr><td colSpan={6}><div className="empty-table"><div className="empty-table-icon"><Truck size={20}/></div><strong>Fleet is not configured yet</strong><p>Add your trucks in the form to enable automatic truck assignment.</p></div></td></tr>}</tbody></table></div></section>
      <aside className="panel form-panel dispatch-form-panel"><div className="panel-heading"><div><h2>Add a truck</h2><p>Set load capacity and per-kilometre running cost.</p></div><span className="panel-heading-icon"><Plus size={17}/></span></div><form action={createDispatchTruck} className="stacked-form"><label className="field-label">Registration number<input name="registration_no" placeholder="e.g. LEA-1234" maxLength={32} required/></label><label className="field-label">Truck name / type<input name="display_name" placeholder="e.g. 10-wheel truck" maxLength={100} required/></label><div className="form-grid form-grid-two"><label className="field-label">Order capacity<input name="capacity_orders" type="number" min="1" max="1000" defaultValue="10" required/></label><label className="field-label">Payload capacity (kg)<input name="capacity_kg" type="number" min="0" step="0.01" defaultValue="0"/></label></div><label className="field-label">Running cost per km (PKR)<input name="cost_per_km" type="number" min="0" step="0.01" defaultValue="0" required/><span className="field-hint">Used for estimates when route distances are entered.</span></label><div className="form-grid form-grid-two"><label className="field-label">Base / current city<input name="current_city" placeholder="e.g. Lahore" maxLength={100}/></label><label className="field-label">Driver name<input name="driver_name" placeholder="Driver full name" maxLength={120}/></label></div><label className="field-label">Driver phone (optional)<input name="driver_phone" type="tel" placeholder="Contact number" maxLength={40}/></label><button className="button button-primary button-full" type="submit"><Plus size={16}/> Add to fleet</button></form><div className="form-note"><Wrench size={15}/><span>Putting a truck in maintenance removes it from auto-assignment. A truck in transit becomes available when its load is confirmed delivered.</span></div></aside></div>
      <div className="notice notice-info"><Truck size={16}/><span><strong>Capacity model:</strong> planning uses order count and, when a kg limit is entered, product unit weights. Truck assignment checks both order capacity and payload when product weights are configured; a zero truck payload means the payload limit is not set.</span></div>
    </div>}

    {activeTab === "targets" && <div className="page-stack dispatch-tab-panel">
      <div className="dispatch-two-column"><section className="panel"><div className="panel-heading"><div><h2>Target performance</h2><p>Compare completed deliveries with the target and extrapolate current pace across each period.</p></div><span className="panel-heading-icon"><Target size={17}/></span></div><div className="dispatch-target-list">{props.targets.map(target => {
        const deliveredInPeriod = deliveredLoads.filter(load => Boolean(load.delivered_at) && load.delivered_at!.slice(0, 10) >= target.starts_on && load.delivered_at!.slice(0, 10) <= target.ends_on);
        const actualDeliveries = deliveredInPeriod.reduce((sum, load) => sum + Number(load.booking_count), 0);
        const actualLoads = deliveredInPeriod.length;
        const totalDays = Math.max(1, Math.floor((new Date(`${target.ends_on}T12:00:00`).getTime() - new Date(`${target.starts_on}T12:00:00`).getTime()) / 86400000) + 1);
        const elapsedDays = Math.max(0, Math.min(totalDays, Math.floor((new Date(`${props.today}T12:00:00`).getTime() - new Date(`${target.starts_on}T12:00:00`).getTime()) / 86400000) + 1));
        const projected = elapsedDays > 0 ? actualDeliveries / elapsedDays * totalDays : 0;
        const progress = Number(target.target_deliveries) > 0 ? Math.min(100, actualDeliveries / Number(target.target_deliveries) * 100) : 0;
        const future = props.today < target.starts_on;
        const ended = props.today > target.ends_on;
        const onPace = Number(target.target_deliveries) === 0 || projected >= Number(target.target_deliveries);
        const stateLabel = future ? "Starts soon" : ended ? (actualDeliveries >= Number(target.target_deliveries) ? "Target achieved" : "Period ended") : onPace ? "On pace" : "Behind pace";
        return <article key={target.id} className="dispatch-target-card"><div className="dispatch-target-top"><div><span className="dispatch-period-pill">{target.period_type}</span><h3>{target.name}</h3><span>{dateLabel(target.starts_on)} — {dateLabel(target.ends_on)}</span></div><span className={`dispatch-target-state ${future ? "state-future" : ended ? "state-ended" : onPace ? "state-on-pace" : "state-behind"}`}>{stateLabel}</span></div><div className="dispatch-target-kpis"><div><strong>{actualDeliveries}</strong><span>Delivered / {target.target_deliveries} target</span></div><div><strong>{Math.round(projected)}</strong><span>Projected at current pace</span></div><div><strong>{actualLoads}</strong><span>Loads delivered / {target.target_loads || "—"}</span></div></div><div className="dispatch-target-progress"><div><span>Delivery target completion</span><strong>{Math.round(progress)}%</strong></div><span className="dispatch-progress-track"><i style={{ width: `${progress}%` }}/></span><small>{elapsedDays} of {totalDays} period days elapsed · projection assumes the average so far continues</small></div>{target.notes && <p className="dispatch-target-notes">{target.notes}</p>}</article>;
      })}{!props.targets.length && <div className="empty-table"><div className="empty-table-icon"><Target size={20}/></div><strong>No active targets</strong><p>Create a weekly, monthly, quarterly, annual, or custom target to see progress and current-pace forecasts.</p></div>}</div></section>
      <aside className="panel form-panel dispatch-form-panel"><div className="panel-heading"><div><h2>Set a dispatch target</h2><p>Targets are saved to your factory workspace.</p></div><span className="panel-heading-icon"><Target size={17}/></span></div><form action={createDispatchTarget} className="stacked-form"><label className="field-label">Target name<input name="name" placeholder="e.g. October delivery goal" maxLength={120} required/></label><label className="field-label">Period<select name="period_type" defaultValue="monthly"><option value="weekly">Weekly</option><option value="monthly">Monthly</option><option value="quarterly">Quarterly</option><option value="annual">Annual</option><option value="custom">Custom period</option></select></label><div className="form-grid form-grid-two"><label className="field-label">Starts on<input name="starts_on" type="date" defaultValue={props.today} required/></label><label className="field-label">Ends on<input name="ends_on" type="date" defaultValue={monthEndIso(props.today)} required/></label></div><label className="field-label">Target deliveries (orders)<input name="target_deliveries" type="number" min="0" step="1" defaultValue="100" required/></label><label className="field-label">Target loads<input name="target_loads" type="number" min="0" step="1" defaultValue="20" required/></label><label className="field-label">Target on-time rate (%)<input name="target_on_time_rate" type="number" min="0" max="100" step="1" defaultValue="90" required/></label><label className="field-label">Notes (optional)<textarea name="notes" placeholder="Shift changes, seasonal context, or delivery commitments" rows={3}/></label><button className="button button-primary button-full" type="submit"><Plus size={16}/> Save target</button></form><div className="form-note"><Gauge size={15}/><span>Forecast is a simple pace projection from completed loads within the target period. On-time performance needs due-date and actual-time data, so it is stored as a target but not yet scored.</span></div></aside></div>
    </div>}

    {activeTab === "warnings" && <div className="page-stack dispatch-tab-panel">
      <section className="panel"><div className="panel-heading"><div><h2>Early warning centre</h2><p>Actionable exceptions from current orders, load assignments, fleet status, stock, and goals.</p></div><span className={`dispatch-warning-total ${props.warnings.some(warning => warning.severity === "critical") ? "has-critical" : ""}`}>{props.warnings.length} open warnings</span></div><div className="dispatch-warning-list">{props.warnings.map(warning => <article key={warning.id} className={`dispatch-warning-card warning-${warning.severity}`}><span className="dispatch-warning-icon">{warning.severity === "critical" ? <AlertOctagon size={18}/> : warning.severity === "warning" ? <AlertTriangle size={18}/> : <Activity size={18}/>}</span><div className="dispatch-warning-copy"><div><span className={`dispatch-severity dispatch-severity-${warning.severity}`}>{warning.severity}</span><strong>{warning.title}</strong></div><p>{warning.detail}</p></div><button type="button" className="button button-secondary button-small" onClick={() => setActiveTab(warning.tab === "loads" ? "loads" : warning.tab)} >Review <ArrowRight size={14}/></button></article>)}{!props.warnings.length && <div className="dispatch-all-clear"><span><CheckCircle2 size={24}/></span><strong>No active dispatch warnings</strong><p>There are no known unplanned approved bookings, unassigned loads, late planned loads, maintenance trucks, or high stock-reservation alerts right now.</p></div>}</div></section>
      <div className="dispatch-two-column dispatch-warning-summary"><section className="panel"><div className="panel-heading"><div><h2>Inventory pressure</h2><p>Products with at least 85% of on-hand inventory reserved.</p></div><span className="panel-heading-icon"><Boxes size={17}/></span></div><div className="table-scroll"><table className="data-table"><thead><tr><th>Product / SKU</th><th>On hand</th><th>Reserved</th><th>Free stock</th><th>Reserved share</th></tr></thead><tbody>{props.products.slice().sort((a,b) => Number(b.stock_reserved)/Math.max(1,Number(b.stock_on_hand))-Number(a.stock_reserved)/Math.max(1,Number(a.stock_on_hand))).slice(0,12).map(product => { const onHand = Number(product.stock_on_hand); const reserved = Number(product.stock_reserved); const pct = onHand > 0 ? Math.min(100, reserved/onHand*100) : 0; return <tr key={product.id}><td><strong>{product.name}</strong><small className="table-muted">{product.sku}</small></td><td>{compactNumber(onHand)}</td><td>{compactNumber(reserved)}</td><td><strong>{compactNumber(onHand-reserved)}</strong></td><td><div className="dispatch-mini-progress"><i className={pct >= 85 ? "progress-risk" : ""} style={{ width: `${pct}%` }}/></div><small className="table-muted">{Math.round(pct)}%</small></td></tr>; })}{!props.products.length && <tr><td colSpan={5}><div className="empty-table">No product inventory yet.</div></td></tr>}</tbody></table></div></section><section className="panel"><div className="panel-heading"><div><h2>Recommended operating rules</h2><p>Checks the module enforces now.</p></div><span className="panel-heading-icon"><ShieldAlert size={17}/></span></div><div className="dispatch-rule-list"><div><CheckCircle2 size={16}/><span><strong>Approved orders only</strong><small>Load planning rejects pending, rejected, cancelled, or cross-workspace bookings.</small></span></div><div><CheckCircle2 size={16}/><span><strong>Reserved stock rechecked</strong><small>Planning validates that selected order quantities are covered by existing reservations.</small></span></div><div><CheckCircle2 size={16}/><span><strong>Truck capacity validated</strong><small>A load cannot depart without a truck; assignments must fit order capacity.</small></span></div><div><CheckCircle2 size={16}/><span><strong>Delivery closes inventory</strong><small>Confirming delivery completes bookings and decrements on-hand and reserved stock together.</small></span></div></div></section></div>
    </div>}

    {activeTab === "incidents" && <div className="page-stack dispatch-tab-panel">
      <div className="dispatch-two-column"><section className="panel"><div className="panel-heading"><div><h2>Contingency & incident log</h2><p>Record issues during loading, travel, or delivery and track the resolution.</p></div><span className="panel-heading-icon"><AlertOctagon size={17}/></span></div>
        <div className="dispatch-contingency-list">{liveContingencies.map(item => { const load = liveLoads.find(candidate => candidate.id === item.load_id); return <article className="dispatch-contingency-item" key={item.id}><div><div className={`contingency-severity contingency-severity-${item.severity}`}>{item.severity} · {item.issue_type.replaceAll("_", " ")} · {item.status}</div><strong>{item.summary}</strong><p>{load?.load_no ?? related(item.dispatch_loads)?.load_no ?? "Dispatch load"} · {new Date(item.created_at).toLocaleString()}{item.notes ? ` · ${item.notes}` : ""}</p>{item.status === "resolved" && item.action_taken && <p><strong>Resolution:</strong> {item.action_taken}</p>}</div>{item.status === "open" && <button type="button" className="button button-secondary button-small" onClick={() => { setResolveContingencyId(item.id); setResolutionText(""); }}>Resolve incident</button>}</article>; })}{!liveContingencies.length && <div className="empty-table"><div className="empty-table-icon"><AlertOctagon size={20}/></div><strong>No contingencies recorded</strong><p>Use “Report issue” on any planned or active load to record a breakdown, accident, road closure, delay, or other event.</p></div>}</div>
      </section><aside className="panel"><div className="panel-heading"><div><h2>Report a new contingency</h2><p>Pick the affected load and capture enough information for an operations decision.</p></div></div><div className="dispatch-rule-list"><div><AlertTriangle size={16}/><span><strong>Critical incidents</strong><small>Accidents, safety events, and dangerous cargo conditions should be escalated immediately through your company’s emergency procedures as well as logged here.</small></span></div><div><CheckCircle2 size={16}/><span><strong>Audit history</strong><small>Reports and resolutions are tied to the workspace, load, and signed-in user.</small></span></div></div><a href="/routes" className="button button-secondary button-full"><MapPin size={14}/> View affected routes</a></aside></div>
    </div>}

    {activeTab === "reports" && <div className="page-stack dispatch-tab-panel">
      <div className="metric-grid metric-grid-four"><div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-blue"><Truck size={17}/></span><span className="metric-trend">All time</span></div><div className="metric-value">{liveLoads.length}</div><div className="metric-label">Created loads</div></div><div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-green"><CheckCircle2 size={17}/></span><span className="metric-trend">Completed</span></div><div className="metric-value">{deliveredOrders}</div><div className="metric-label">Delivered orders</div></div><div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-amber"><Wallet size={17}/></span><span className="metric-trend">Entered cost estimates</span></div><div className="metric-value metric-value-small">{money(estimatedSpend)}</div><div className="metric-label">Cost on delivered / in-transit loads</div></div><div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-violet"><Users size={17}/></span><span className="metric-trend">Fleet</span></div><div className="metric-value">{liveTrucks.length ? Math.round(availableTrucks.length / liveTrucks.length * 100) : 0}<span className="metric-suffix">%</span></div><div className="metric-label">Trucks currently available</div></div></div>
      <section className="panel"><div className="panel-heading"><div><h2>Load performance ledger</h2><p>Use the CSV export for analysis in Excel or your accounting workflow. Estimated cost remains zero until route distance/cost is entered.</p></div><button type="button" className="button button-secondary button-small" onClick={exportCsv}><Download size={14}/> Download CSV</button></div><div className="table-scroll"><table className="data-table"><thead><tr><th>Load / created</th><th>Destination sequence</th><th>Grouping</th><th>Orders</th><th>Weight</th><th>Truck</th><th>Status</th><th>Est. cost</th><th>Planned date</th></tr></thead><tbody>{liveLoads.map(load => { const truck = related(load.dispatch_trucks); return <tr key={load.id}><td><strong>{load.load_no}</strong><small className="table-muted">{dateLabel(load.created_at)}</small></td><td><strong>{load.destination_summary || "Destination not set"}</strong><small className="table-muted">{Array.isArray(load.stop_plan) ? load.stop_plan.length : 0} stops</small></td><td>{GROUPING_MODES.find(mode => mode.value === load.grouping_mode)?.label ?? load.grouping_mode}</td><td><strong>{load.booking_count}</strong><small className="table-muted">of {load.capacity_orders} capacity</small></td><td>{Number(load.estimated_weight_kg ?? 0) > 0 ? `${compactNumber(load.estimated_weight_kg)} kg` : "—"}</td><td>{truck?.registration_no ?? "Unassigned"}</td><td><span className={loadStatusClass(load.status)}>{load.status.replace("_", " ")}</span></td><td>{money(Number(load.estimated_cost ?? 0))}</td><td>{load.planned_delivery_date ? dateLabel(load.planned_delivery_date) : "—"}</td></tr>; })}{!liveLoads.length && <tr><td colSpan={9}><div className="empty-table"><div className="empty-table-icon"><Activity size={20}/></div><strong>No reportable loads yet</strong><p>Once load plans are created, delivery and fleet activity will appear here.</p></div></td></tr>}</tbody></table></div></section>
      <div className="notice notice-info"><Activity size={16}/><span><strong>Reporting notes:</strong> completed orders are counted at load delivery; utilization is order count divided by the planned capacity; costs include entered estimates for delivered and in-transit loads. On-time rate and true route savings need planned/actual distance, due times, and fuel/expense data.</span></div>
    </div>}

    {activeTab === "destinations" && <div className="page-stack dispatch-tab-panel">
      <section className="panel"><div className="panel-heading"><div><h2>Destination hierarchy</h2><p>Set the address levels used by city, province, region, district, tehsil, area, zone, and route consolidation.</p></div><span className="table-count">{props.customers.length} customers</span></div><div className="dispatch-destination-help"><MapPin size={16}/><span>Changes are synced to pending and approved bookings for the same customer. Completed or cancelled bookings retain their historical destination.</span></div><div className="dispatch-destination-toolbar"><label className="search-field"><Search size={14}/><input value={customerSearch} onChange={event => setCustomerSearch(event.target.value)} placeholder="Search customer or city…"/></label></div><div className="table-scroll"><table className="data-table dispatch-destination-table"><thead><tr><th>Customer</th><th>City</th><th>Region</th><th>Province</th><th>District</th><th>Tehsil</th><th>Area</th><th>Zone</th><th>Delivery address</th><th>Latitude</th><th>Longitude</th><th>Save</th></tr></thead><tbody>{props.customers.filter(customer => !customerSearch || [customer.name, customer.customer_code, customer.city, customer.region].some(value => value.toLowerCase().includes(customerSearch.toLowerCase()))).map(customer => <tr key={customer.id}><td><strong>{customer.name}</strong><small className="table-muted">{customer.customer_code}</small></td><td colSpan={11}><form action={updateCustomerDestination} className="dispatch-destination-edit"><input type="hidden" name="customer_id" value={customer.id}/><input aria-label={`${customer.name} city`} name="city" defaultValue={customer.city} placeholder="City"/><input aria-label={`${customer.name} region`} name="region" defaultValue={customer.region} placeholder="Region"/><input aria-label={`${customer.name} province`} name="province" defaultValue={customer.province} placeholder="Province"/><input aria-label={`${customer.name} district`} name="district" defaultValue={customer.district} placeholder="District"/><input aria-label={`${customer.name} tehsil`} name="tehsil" defaultValue={customer.tehsil} placeholder="Tehsil"/><input aria-label={`${customer.name} area`} name="area" defaultValue={customer.area} placeholder="Area"/><input aria-label={`${customer.name} zone`} name="zone" defaultValue={customer.zone} placeholder="Zone"/><input aria-label={`${customer.name} delivery address`} className="destination-address-input" name="delivery_address" defaultValue={customer.delivery_address} placeholder="Street / delivery address"/><input aria-label={`${customer.name} latitude`} name="latitude" type="number" min="-90" max="90" step="0.0000001" defaultValue={customer.latitude ?? ""} placeholder="Latitude"/><input aria-label={`${customer.name} longitude`} name="longitude" type="number" min="-180" max="180" step="0.0000001" defaultValue={customer.longitude ?? ""} placeholder="Longitude"/><button type="submit" className="button button-secondary button-xs">Save location</button></form></td></tr>)}{!props.customers.length && <tr><td colSpan={12}><div className="empty-table"><div className="empty-table-icon"><MapPin size={20}/></div><strong>No active customers</strong><p>Create customers before planning destinations.</p></div></td></tr>}</tbody></table></div></section>
    </div>}
    {loadingLoadId && <div className="dispatch-modal-backdrop" role="presentation" onMouseDown={event => { if (event.target === event.currentTarget) setLoadingLoadId(null); }}><form className="dispatch-modal" role="dialog" aria-modal="true" aria-labelledby="loading-modal-title" onSubmit={event => { event.preventDefault(); void runCommand("complete_loading", { load_id: loadingLoadId, action: "finish_loading", checklist: loadingChecklist, loading_notes: loadingNotes }, `loading:${loadingLoadId}`); }}>
      <div className="dispatch-modal-header"><div><h2 id="loading-modal-title">Loading verification</h2><p>{liveLoads.find(load => load.id === loadingLoadId)?.load_no ?? "Dispatch load"} · confirm each check before marking the load ready.</p></div><button type="button" className="icon-button" aria-label="Close" onClick={() => setLoadingLoadId(null)}><X size={18}/></button></div>
      <div className="loading-checklist">{([ ["quantities_verified","Quantities match the pick list"], ["packages_checked","Packages and condition checked"], ["cargo_secured","Cargo is safely secured"], ["documents_ready","Delivery documents and customer stops are ready"] ] as const).map(([key,label]) => <label className="loading-check-row" key={key}><input type="checkbox" checked={loadingChecklist[key]} onChange={event => setLoadingChecklist(current => ({ ...current, [key]: event.target.checked }))}/><span><strong>{label}</strong><small>Required before this load can move to “Ready to dispatch”.</small></span></label>)}</div>
      <label className="field-label loading-notes-label">Loading notes (optional)<textarea value={loadingNotes} maxLength={1000} onChange={event => setLoadingNotes(event.target.value)} placeholder="Pallet count, seal number, special handling…"/></label>
      <div className="dispatch-modal-footer"><button type="button" className="button button-secondary" onClick={() => setLoadingLoadId(null)}>Back</button><button type="submit" className="button button-primary" disabled={!Object.values(loadingChecklist).every(Boolean) || commandBusy === `loading:${loadingLoadId}`}>{commandBusy === `loading:${loadingLoadId}` ? <span className="dispatch-spinner"/> : <CheckCircle2 size={15}/>} Mark ready to dispatch</button></div>
    </form></div>}

    {contingencyLoadId && <div className="dispatch-modal-backdrop" role="presentation" onMouseDown={event => { if (event.target === event.currentTarget) setContingencyLoadId(null); }}><form className="dispatch-modal" role="dialog" aria-modal="true" aria-labelledby="contingency-modal-title" onSubmit={event => { event.preventDefault(); void runCommand("report_contingency", { load_id: contingencyLoadId, issue_type: contingencyType, severity: contingencySeverity, summary: contingencySummary, notes: contingencyNotes }, "contingency"); }}>
      <div className="dispatch-modal-header"><div><h2 id="contingency-modal-title">Report dispatch contingency</h2><p>Record a problem for {liveLoads.find(load => load.id === contingencyLoadId)?.load_no ?? "this load"}. This creates an auditable incident record.</p></div><button type="button" className="icon-button" aria-label="Close" onClick={() => setContingencyLoadId(null)}><X size={18}/></button></div>
      <div className="dispatch-modal-grid"><label className="field-label">Issue type<select value={contingencyType} onChange={event => setContingencyType(event.target.value)}><option value="breakdown">Vehicle breakdown</option><option value="accident">Accident</option><option value="road_closure">Road closure</option><option value="weather">Weather</option><option value="customer_unavailable">Customer unavailable</option><option value="cargo_damage">Cargo damage</option><option value="stock_discrepancy">Stock discrepancy</option><option value="driver_issue">Driver issue</option><option value="delay">Delivery delay</option><option value="other">Other</option></select></label><label className="field-label">Severity<select value={contingencySeverity} onChange={event => setContingencySeverity(event.target.value)}><option value="low">Low</option><option value="medium">Medium</option><option value="high">High</option><option value="critical">Critical</option></select></label><label className="field-label span-all">Short summary<input required minLength={3} maxLength={180} value={contingencySummary} onChange={event => setContingencySummary(event.target.value)} placeholder="e.g. Truck overheated on M-2 motorway"/></label><label className="field-label span-all">Details / action needed<textarea value={contingencyNotes} onChange={event => setContingencyNotes(event.target.value)} maxLength={2000} placeholder="Location, safety risks, contact attempts, cargo status…"/></label></div>
      <div className="dispatch-modal-footer"><button type="button" className="button button-secondary" onClick={() => setContingencyLoadId(null)}>Cancel</button><button type="submit" className="button button-primary" disabled={commandBusy === "contingency" || contingencySummary.trim().length < 3}>{commandBusy === "contingency" ? <span className="dispatch-spinner"/> : <AlertOctagon size={15}/>} Submit incident</button></div>
    </form></div>}

    {resolveContingencyId && <div className="dispatch-modal-backdrop" role="presentation" onMouseDown={event => { if (event.target === event.currentTarget) setResolveContingencyId(null); }}><form className="dispatch-modal" role="dialog" aria-modal="true" aria-labelledby="resolve-modal-title" onSubmit={event => { event.preventDefault(); void runCommand("resolve_contingency", { contingency_id: resolveContingencyId, action_taken: resolutionText }, `resolve:${resolveContingencyId}`); }}>
      <div className="dispatch-modal-header"><div><h2 id="resolve-modal-title">Resolve contingency</h2><p>Record what was done before closing this incident.</p></div><button type="button" className="icon-button" aria-label="Close" onClick={() => setResolveContingencyId(null)}><X size={18}/></button></div>
      <label className="field-label">Resolution / action taken<textarea required minLength={3} maxLength={2000} value={resolutionText} onChange={event => setResolutionText(event.target.value)} placeholder="e.g. Replacement truck dispatched; cargo checked and transfer completed."/></label>
      <div className="dispatch-modal-footer"><button type="button" className="button button-secondary" onClick={() => setResolveContingencyId(null)}>Cancel</button><button type="submit" className="button button-primary" disabled={commandBusy === `resolve:${resolveContingencyId}` || resolutionText.trim().length < 3}>{commandBusy === `resolve:${resolveContingencyId}` ? <span className="dispatch-spinner"/> : <CheckCircle2 size={15}/>} Resolve incident</button></div>
    </form></div>}

    {truckPassLoadId && activeTruckPass && <div className="dispatch-modal-backdrop bill-pass-backdrop" role="presentation" onMouseDown={event => { if (event.target === event.currentTarget) setTruckPassLoadId(null); }}><section className="dispatch-modal truck-pass-modal" role="dialog" aria-modal="true" aria-labelledby="truck-pass-title">
      <div className="bill-pass-screen-actions"><span className={`truck-pass-status truck-pass-status-${activeTruckPass.status}`}>{activeTruckPass.status.replaceAll("_", " ")}</span><button type="button" className="button button-secondary button-small" onClick={() => setTruckPassLoadId(null)}>Close</button><button type="button" className="button button-primary button-small" onClick={() => window.print()}><Printer size={14}/> Print truck pass</button></div>
      <form onSubmit={event => { event.preventDefault(); void runCommand("complete_truck_pass", { load_id: truckPassLoadId, checklist: truckPassChecklist, inspection_notes: truckPassNotes }, `truck-pass:${truckPassLoadId}`); }}>
        <div className="truck-pass-print bill-pass-print"><div className="bill-pass-topline"><div><div className="bill-pass-kicker">SupplyOS · Vehicle gate control</div><h2 id="truck-pass-title">TRUCK INSPECTION / GATE PASS</h2><small>Pre-departure checks · Not a government transport permit</small></div><div className="bill-pass-number">{activeTruckPass.pass_no}<br/><small>Status: {activeTruckPass.status.replaceAll("_", " ")}</small><br/><small>Generated {new Date(activeTruckPass.issued_at).toLocaleString("en-PK", { dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Karachi" })}</small></div></div>
          <div className="bill-pass-grid"><div className="bill-pass-fact"><small>Factory / gate</small><strong>{String(activeTruckPassFactorySnapshot.name ?? "Factory")}</strong><div>{String(activeTruckPassFactorySnapshot.address ?? "Factory address not set")}</div></div><div className="bill-pass-fact"><small>Vehicle / driver</small><strong>{String(activeTruckPassTruckSnapshot.registration_no ?? "")}</strong><div>{String(activeTruckPassTruckSnapshot.display_name ?? "")} · {String(activeTruckPassTruckSnapshot.driver_name ?? "Driver not set")}</div><div>{String(activeTruckPassTruckSnapshot.driver_phone ?? "")}</div></div><div className="bill-pass-fact"><small>Load / route</small><strong>{String(activeTruckPassLoadSnapshot.load_no ?? liveLoads.find(load => load.id === truckPassLoadId)?.load_no ?? "")}</strong><div>{String(activeTruckPassLoadSnapshot.destination_summary ?? "")}</div></div><div className="bill-pass-fact"><small>Load summary</small><strong>{String(activeTruckPassLoadSnapshot.booking_count ?? 0)} orders · {compactNumber(Number(activeTruckPassLoadSnapshot.estimated_weight_kg ?? 0))} kg</strong><div>{String(activeTruckPassLoadSnapshot.planned_distance_km ?? 0)} planned km</div></div></div>
          <div className="loading-checklist truck-pass-checklist">{TRUCK_PASS_CHECKS.map(item => <label className="loading-check-row" key={item.key}><input type="checkbox" disabled={liveLoads.find(load => load.id === truckPassLoadId)?.status !== "ready"} checked={!!truckPassChecklist[item.key]} onChange={event => setTruckPassChecklist(current => ({ ...current, [item.key]: event.target.checked }))}/><span><strong>{item.label}</strong><small>{item.detail}</small></span></label>)}</div>
          <label className="field-label loading-notes-label">Inspection findings / defects<textarea disabled={liveLoads.find(load => load.id === truckPassLoadId)?.status !== "ready"} maxLength={2000} value={truckPassNotes} onChange={event => setTruckPassNotes(event.target.value)} placeholder="Record defects, repairs required, seal number or inspection notes…"/></label>
          <div className="truck-pass-print-notes"><strong>Inspection findings / defects</strong><p>{truckPassNotes.trim() || "No inspection findings recorded."}</p></div>
          <div className="bill-pass-note"><strong>Gate control:</strong> A truck cannot be dispatched from SupplyOS until all eight checks are marked complete and the pass is cleared. Any missing/failed check puts the pass on HOLD.</div>
          {liveLoads.find(load => load.id === truckPassLoadId)?.status === "ready" && <div className="dispatch-modal-footer"><button type="button" className="button button-secondary" onClick={() => setTruckPassLoadId(null)}>Cancel</button><button type="submit" className="button button-primary" disabled={commandBusy === `truck-pass:${truckPassLoadId}`}>{commandBusy === `truck-pass:${truckPassLoadId}` ? <span className="dispatch-spinner"/> : <CheckCircle2 size={15}/>} {Object.values(truckPassChecklist).every(Boolean) ? "Save inspection / clear gate pass" : "Save inspection / set HOLD"}</button></div>}
          {activeTruckPass.checked_at && <p className="table-muted">Last inspection submitted {new Date(activeTruckPass.checked_at).toLocaleString("en-PK", { dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Karachi" })} · Pass number is unique and auditable.</p>}
        </div>
      </form></section></div>}

    {billPass && <div className="dispatch-modal-backdrop bill-pass-backdrop" role="presentation" onMouseDown={event => { if (event.target === event.currentTarget) setBillPass(null); }}><section className="dispatch-modal bill-pass-modal" role="dialog" aria-modal="true" aria-labelledby="bill-pass-title"><div className="bill-pass-screen-actions"><span className="muted">Review before printing · PKR</span><button type="button" className="button button-secondary button-small" onClick={() => setBillPass(null)}>Close</button><button type="button" className="button button-primary button-small" onClick={() => window.print()}><Printer size={14}/> Print bill pass</button></div>
      <div className="bill-pass-print"><div className="bill-pass-topline"><div><div className="bill-pass-kicker">SupplyOS · Dispatch document</div><h2 id="bill-pass-title">GOODS DISPATCH BILL / PASS</h2><small>Driver's delivery manifest</small></div><div className="bill-pass-number">{billPass.bill_pass_no}<br/><small>Issued {new Date(billPass.issued_at).toLocaleString("en-PK", { dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Karachi" })}</small></div></div>
      <div className="bill-pass-grid"><div className="bill-pass-fact"><small>Load / route</small><strong>{String(billPass.content_snapshot.load.load_no ?? "")}</strong><div>{String(billPass.content_snapshot.load.destination_summary ?? "")}</div></div><div className="bill-pass-fact"><small>Vehicle / driver</small><strong>{String(billPass.content_snapshot.truck.registration_no ?? "")} · {String(billPass.content_snapshot.truck.display_name ?? "")}</strong><div>{String(billPass.content_snapshot.truck.driver_name ?? "Driver not set")} · {String(billPass.content_snapshot.truck.driver_phone ?? "")}</div></div><div className="bill-pass-fact"><small>Delivery date</small><strong>{String(billPass.content_snapshot.load.planned_delivery_date ?? "Not specified")}</strong></div><div className="bill-pass-fact"><small>Declared operational summary</small><strong>{String(billPass.content_snapshot.load.booking_count ?? 0)} orders · {compactNumber(Number(billPass.content_snapshot.load.estimated_weight_kg ?? 0))} kg</strong><div>{String(billPass.content_snapshot.load.planned_distance_km ?? 0)} planned km</div></div></div>
      <table className="bill-pass-table"><thead><tr><th># / Order</th><th>Shop / Consignee & address</th><th>Goods summary</th><th>Order value (PKR)</th></tr></thead><tbody>{billPass.content_snapshot.orders.map((order,index) => { const items = Array.isArray(order.items) ? order.items as Array<Record<string, unknown>> : []; return <tr key={`${String(order.booking_no ?? index)}`}><td>{index+1}<br/>{String(order.booking_no ?? "")}</td><td><strong>{String(order.customer_name ?? "")}</strong><br/>{String(order.address ?? "")}<br/>{[order.city, order.district, order.province].map(value => String(value ?? "")).filter(Boolean).join(", ")}<br/>{String(order.phone ?? "")}</td><td>{items.map(item => `${String(item.name ?? item.sku ?? "Item")} × ${String(item.quantity ?? 0)} ${String(item.unit ?? "")}`).join("; ")}</td><td>{money(Number(order.order_value ?? 0))}</td></tr>; })}</tbody></table>
      <div className="bill-pass-note"><strong>Important document notice:</strong> {billPass.content_snapshot.notice} This manifest lists goods and destination orders for dispatch reference; it does not replace any government-issued permit, tax invoice, transport document, or other legally required paperwork.</div>
      <div className="bill-pass-signatures"><div>Prepared by / dispatch control</div><div>Driver acknowledgement</div><div>Gate / security verification</div></div></div></section></div>}
  </div>;
}
