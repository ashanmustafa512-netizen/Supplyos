import type { Metadata } from "next";
import { getWorkspace, requireUser } from "@/lib/server-auth";
import { canManageFleetTracking } from "@/lib/access";
import { RouteConsole } from "@/components/route-console";
import type { EmployeeLocation, RouteFactory, RouteLoad, RouteTruck, Stop } from "@/components/route-map";

type Relation<T> = T | T[] | null | undefined;
const one = <T,>(value: Relation<T>): T | null => Array.isArray(value) ? value[0] ?? null : (value ?? null) as T | null;

export const metadata: Metadata = { title: "Routes & geofencing" };

function mapTruck(raw: Record<string, unknown>): RouteTruck {
  return {
    id: String(raw.id), registrationNo: String(raw.registration_no ?? ""), name: String(raw.display_name ?? "Truck"),
    driverName: String(raw.driver_name ?? ""), status: String(raw.status ?? "unknown"),
    latitude: raw.current_latitude == null ? null : Number(raw.current_latitude),
    longitude: raw.current_longitude == null ? null : Number(raw.current_longitude),
    locationUpdatedAt: raw.location_updated_at == null ? null : String(raw.location_updated_at),
    factoryDistanceM: raw.factory_distance_m == null ? null : Number(raw.factory_distance_m),
    factoryGeofenceState: String(raw.factory_geofence_state ?? "unknown"),
    factoryGeofenceCheckedAt: raw.factory_geofence_checked_at == null ? null : String(raw.factory_geofence_checked_at),
    currentCity: String(raw.current_city ?? ""), capacityOrders: Number(raw.capacity_orders ?? 0), capacityKg: Number(raw.capacity_kg ?? 0),
    locationSource: String(raw.location_source ?? "manual"), locationAccuracyM: raw.current_location_accuracy_m == null ? null : Number(raw.current_location_accuracy_m),
  };
}

export default async function RoutesPage() {
  const { supabase, user } = await requireUser();
  const { membership } = await getWorkspace(supabase, user.id);
  const orgId = membership?.organization_id;
  const [loadResult, incidentResult, geofenceResult, truckResult, factoryResult, employeeResult] = await Promise.all([
    supabase.from("dispatch_loads").select(`
      id, load_no, status, destination_summary, geofence_radius_m, assigned_truck_id,
      dispatch_trucks(id, registration_no, display_name, driver_name, status, current_latitude, current_longitude, location_updated_at, factory_distance_m, factory_geofence_state, factory_geofence_checked_at, current_city, capacity_orders, capacity_kg, location_source, current_location_accuracy_m),
      dispatch_load_bookings(id, booking_id, stop_order,
        bookings(id, booking_no, city, province, delivery_address, latitude, longitude,
          customers(name, customer_code, phone)))
    `).in("status", ["planned", "ready", "in_transit"]).order("stop_order", { referencedTable: "dispatch_load_bookings", ascending: true }).order("created_at", { ascending: false }).limit(500),
    supabase.from("dispatch_contingencies").select("id, load_id, issue_type, severity, summary, status, created_at, dispatch_loads(load_no)").order("created_at", { ascending: false }).limit(100),
    supabase.from("dispatch_geofence_states").select("load_id, booking_id, state, distance_m, radius_m, last_checked_at").order("last_checked_at", { ascending: false }).limit(1000),
    supabase.from("dispatch_trucks").select("id, registration_no, display_name, driver_name, driver_phone, status, current_latitude, current_longitude, location_updated_at, factory_distance_m, factory_geofence_state, factory_geofence_checked_at, current_city, capacity_orders, capacity_kg, location_source, current_location_accuracy_m, notes").order("created_at", { ascending: false }).limit(500),
    orgId ? supabase.from("organizations").select("id, name, factory_address, factory_latitude, factory_longitude, factory_geofence_radius_m").eq("id", orgId).maybeSingle() : Promise.resolve({ data: null, error: null }),
    orgId ? supabase.from("employee_location_sessions").select("id,user_id,employee_name,current_latitude,current_longitude,last_location_at,current_location_accuracy_m,factory_distance_m,factory_geofence_state,started_at").eq("organization_id", orgId).is("ended_at", null).order("started_at", { ascending: false }).limit(500) : Promise.resolve({ data: [], error: null }),
  ]);

  const fleetTrucks = ((truckResult.data ?? []) as unknown as Array<Record<string, unknown>>).map(mapTruck);
  const geofences = new Map(((geofenceResult.data ?? []) as unknown as Array<Record<string, unknown>>).map(row => [String(row.load_id) + ":" + String(row.booking_id), row]));
  const routes: RouteLoad[] = ((loadResult.data ?? []) as unknown as Array<Record<string, unknown>>).map(raw => {
    const rawTruck = one(raw.dispatch_trucks as Relation<Record<string, unknown>>);
    const truck = rawTruck ? mapTruck(rawTruck) : null;
    const stops = ((raw.dispatch_load_bookings ?? []) as Array<Record<string, unknown>>).map(link => {
      const booking = one(link.bookings as Relation<Record<string, unknown>>);
      if (!booking) return null;
      const customer = one(booking.customers as Relation<Record<string, unknown>>);
      const geofence = geofences.get(String(raw.id) + ":" + String(booking.id));
      return {
        bookingId: String(booking.id), bookingNo: String(booking.booking_no ?? "Order"),
        customerName: String(customer?.name ?? "Shop / customer"), customerCode: String(customer?.customer_code ?? ""),
        address: String(booking.delivery_address ?? ""), city: String(booking.city ?? ""), province: String(booking.province ?? ""),
        latitude: booking.latitude == null ? null : Number(booking.latitude), longitude: booking.longitude == null ? null : Number(booking.longitude),
        phone: String(customer?.phone ?? ""), geofenceState: geofence ? String(geofence.state ?? "not_checked") : "not_checked",
        distanceM: geofence && geofence.distance_m != null ? Number(geofence.distance_m) : null,
        geofenceLastCheckedAt: geofence?.last_checked_at == null ? null : String(geofence.last_checked_at),
      } satisfies Stop;
    }).filter(Boolean) as Stop[];
    return { id: String(raw.id), loadNo: String(raw.load_no ?? "Load"), status: String(raw.status ?? "planned"),
      destinationSummary: String(raw.destination_summary ?? ""), radiusM: Number(raw.geofence_radius_m ?? 250), truck, stops };
  });
  const rawFactory = factoryResult.data as Record<string, unknown> | null;
  const factory: RouteFactory | null = rawFactory ? {
    name: String(rawFactory.name ?? "Factory"), address: String(rawFactory.factory_address ?? ""),
    latitude: rawFactory.factory_latitude == null ? null : Number(rawFactory.factory_latitude),
    longitude: rawFactory.factory_longitude == null ? null : Number(rawFactory.factory_longitude),
    radiusM: Number(rawFactory.factory_geofence_radius_m ?? 250),
  } : null;
  const employees: EmployeeLocation[] = ((employeeResult.data ?? []) as unknown as Array<Record<string, unknown>>).map(row => ({
    id: String(row.id), userId: String(row.user_id), employeeName: String(row.employee_name ?? "Employee"),
    latitude: row.current_latitude == null ? null : Number(row.current_latitude), longitude: row.current_longitude == null ? null : Number(row.current_longitude),
    locationUpdatedAt: row.last_location_at == null ? null : String(row.last_location_at), accuracyM: row.current_location_accuracy_m == null ? null : Number(row.current_location_accuracy_m),
    distanceM: row.factory_distance_m == null ? null : Number(row.factory_distance_m), geofenceState: String(row.factory_geofence_state ?? "unknown"), startedAt: String(row.started_at),
  }));
  const incidents = (incidentResult.data ?? []) as unknown as Parameters<typeof RouteConsole>[0]["incidents"];
  const databaseError = [loadResult.error, incidentResult.error, geofenceResult.error, truckResult.error, factoryResult.error, employeeResult.error].find(Boolean)?.message;

  return <>
    {databaseError ? <div className="notice notice-error">Route data could not fully load: {databaseError}. Confirm the fleet geofencing migration was applied to the Supabase project configured for this app.</div> : null}
    <RouteConsole initialRoutes={routes} initialTrucks={fleetTrucks} initialFactory={factory} initialEmployees={employees} canManageEmployeeLocations={canManageFleetTracking(membership?.role)} incidents={incidents}/>
  </>;
}
