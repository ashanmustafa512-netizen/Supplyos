"use client";

import { useEffect, useRef, useState, type FormEvent } from "react";
import { AlertTriangle, CheckCircle2, MapPin, Navigation, RefreshCw, Route as RouteIcon, Truck, LocateFixed, MapPinned, Radio, Save, Square } from "lucide-react";
import { RouteMap, type EmployeeLocation, type RouteFactory, type RouteLoad, type RouteTruck } from "@/components/route-map";
import { runDispatchCommand } from "@/app/(app)/dispatch/actions";
import { createClient } from "@/lib/supabase/client";

type Incident = { id: string; load_id: string; issue_type: string; severity: string; summary: string; status: string; created_at: string; dispatch_loads?: { load_no: string } | { load_no: string }[] | null };
type TruckRow = { id: string; registration_no: string; display_name: string; driver_name: string; status: string; current_latitude: number | string | null; current_longitude: number | string | null; location_updated_at: string | null; factory_distance_m: number | string | null; factory_geofence_state: string | null; factory_geofence_checked_at: string | null; current_city: string | null; capacity_orders: number | string | null; capacity_kg: number | string | null; location_source?: string | null; current_location_accuracy_m?: number | string | null };
const one = <T,>(value: T | T[] | null | undefined): T | null => Array.isArray(value) ? value[0] ?? null : value ?? null;

function fromTruckRow(row: TruckRow): RouteTruck {
  return { id: row.id, registrationNo: row.registration_no, name: row.display_name, driverName: row.driver_name ?? "", status: row.status,
    latitude: row.current_latitude == null ? null : Number(row.current_latitude), longitude: row.current_longitude == null ? null : Number(row.current_longitude),
    locationUpdatedAt: row.location_updated_at, factoryDistanceM: row.factory_distance_m == null ? null : Number(row.factory_distance_m),
    factoryGeofenceState: row.factory_geofence_state ?? "unknown", factoryGeofenceCheckedAt: row.factory_geofence_checked_at,
    currentCity: row.current_city ?? "", capacityOrders: Number(row.capacity_orders ?? 0), capacityKg: Number(row.capacity_kg ?? 0), locationSource: row.location_source ?? "manual", locationAccuracyM: row.current_location_accuracy_m == null ? null : Number(row.current_location_accuracy_m) };
}
function formatDistance(distanceM: number | null | undefined) {
  if (distanceM == null || !Number.isFinite(distanceM)) return "Distance unavailable";
  return distanceM < 1000 ? `${Math.round(distanceM)} m` : `${(distanceM / 1000).toFixed(1)} km`;
}
function distanceBetween(lat1: number, lon1: number, lat2: number, lon2: number) {
  const toRad = (number: number) => number * Math.PI / 180;
  const a = Math.sin(toRad(lat2 - lat1) / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(toRad(lon2 - lon1) / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.sqrt(Math.min(1, a)));
}
function factoryDistance(truck: RouteTruck, factory: RouteFactory | null) {
  if (factory?.latitude != null && factory.longitude != null && truck.latitude != null && truck.longitude != null) {
    return distanceBetween(factory.latitude, factory.longitude, truck.latitude, truck.longitude);
  }
  return truck.factoryDistanceM ?? null;
}

export function RouteConsole({ initialRoutes, initialTrucks, initialFactory, initialEmployees, canManageEmployeeLocations, incidents }: { initialRoutes: RouteLoad[]; initialTrucks: RouteTruck[]; initialFactory: RouteFactory | null; initialEmployees: EmployeeLocation[]; canManageEmployeeLocations: boolean; incidents: Incident[] }) {
  const [routes, setRoutes] = useState(initialRoutes);
  const [trucks, setTrucks] = useState(initialTrucks);
  const [factory, setFactory] = useState<RouteFactory | null>(initialFactory);
  const [employees, setEmployees] = useState<EmployeeLocation[]>(initialEmployees);
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [coordinates, setCoordinates] = useState<Record<string, { lat: string; lng: string }>>(() => Object.fromEntries(initialTrucks.map(truck => [truck.id, { lat: truck.latitude == null ? "" : String(truck.latitude), lng: truck.longitude == null ? "" : String(truck.longitude) }])));
  const [radii, setRadii] = useState<Record<string, string>>(() => Object.fromEntries(initialRoutes.map(route => [route.id, String(route.radiusM || 250)])));
  const [factoryAddress, setFactoryAddress] = useState(initialFactory?.address ?? "");
  const [factoryLat, setFactoryLat] = useState(initialFactory?.latitude == null ? "" : String(initialFactory.latitude));
  const [factoryLng, setFactoryLng] = useState(initialFactory?.longitude == null ? "" : String(initialFactory.longitude));
  const [factoryRadius, setFactoryRadius] = useState(String(initialFactory?.radiusM ?? 250));
  const [gpsTruckId, setGpsTruckId] = useState(initialTrucks.find(truck => truck.status === "in_transit")?.id ?? initialTrucks[0]?.id ?? "");
  const [gpsSharing, setGpsSharing] = useState(false);
  const [lastGpsSentAt, setLastGpsSentAt] = useState<string | null>(null);
  const [lastRefreshAt, setLastRefreshAt] = useState(() => new Date().toISOString());
  const watchIdRef = useRef<number | null>(null);
  const lastGpsSendMsRef = useRef(0);
  const gpsSendingRef = useRef(false);
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    const supabase = createClient();
    async function refreshLocations() {
      const [{ data, error }, { data: activeLoads }, { data: factoryRow }, { data: employeeRows }] = await Promise.all([
        supabase.from("dispatch_trucks").select("id,registration_no,display_name,driver_name,status,current_latitude,current_longitude,location_updated_at,factory_distance_m,factory_geofence_state,factory_geofence_checked_at,current_city,capacity_orders,capacity_kg,location_source,current_location_accuracy_m").order("created_at", { ascending: false }).limit(500),
        supabase.from("dispatch_loads").select("id").in("status", ["ready", "in_transit"]).limit(500),
        supabase.from("memberships").select("organization_id").limit(1).maybeSingle(),
        supabase.from("employee_location_sessions").select("id,user_id,employee_name,current_latitude,current_longitude,last_location_at,current_location_accuracy_m,factory_distance_m,factory_geofence_state,started_at").is("ended_at", null).order("started_at", { ascending: false }).limit(500),
      ]);
      if (!mountedRef.current || error || !data) return;
      const updated = (data as unknown as TruckRow[]).map(fromTruckRow);
      const activeIds = (activeLoads ?? []).map(load => load.id);
      const { data: states } = activeIds.length
        ? await supabase.from("dispatch_geofence_states").select("load_id,booking_id,state,distance_m,radius_m,last_checked_at").in("load_id", activeIds).limit(2000)
        : { data: [] as Array<Record<string, unknown>> };
      if (!mountedRef.current) return;
      const stateByKey = new Map<string, Record<string, unknown>>((states ?? []).map(state => [
        String((state as Record<string, unknown>).load_id) + ":" + String((state as Record<string, unknown>).booking_id),
        state as Record<string, unknown>,
      ]));
      const updatedAt = new Date().toISOString();
      setTrucks(updated);
      setEmployees(((employeeRows ?? []) as unknown as Array<Record<string, unknown>>).map(row => ({
        id: String(row.id), userId: String(row.user_id), employeeName: String(row.employee_name ?? "Employee"),
        latitude: row.current_latitude == null ? null : Number(row.current_latitude), longitude: row.current_longitude == null ? null : Number(row.current_longitude),
        locationUpdatedAt: row.last_location_at == null ? null : String(row.last_location_at), accuracyM: row.current_location_accuracy_m == null ? null : Number(row.current_location_accuracy_m),
        distanceM: row.factory_distance_m == null ? null : Number(row.factory_distance_m), geofenceState: String(row.factory_geofence_state ?? "unknown"), startedAt: String(row.started_at),
      })));
      setRoutes(current => current.map(route => ({
        ...route,
        truck: route.truck ? updated.find(truck => truck.id === route.truck?.id) ?? route.truck : null,
        stops: route.stops.map(stop => {
          const state = stateByKey.get(route.id + ":" + stop.bookingId);
          return state ? { ...stop, geofenceState: String(state.state ?? "not_checked"), distanceM: state.distance_m == null ? null : Number(state.distance_m), geofenceLastCheckedAt: state.last_checked_at == null ? null : String(state.last_checked_at) } : stop;
        }),
      })));
      setLastRefreshAt(updatedAt);
      // Factory configuration is refreshed only when this workspace membership can be resolved.
      if (factoryRow?.organization_id) {
        const { data: org } = await supabase.from("organizations").select("name,factory_address,factory_latitude,factory_longitude,factory_geofence_radius_m").eq("id", factoryRow.organization_id).maybeSingle();
        if (mountedRef.current && org) {
          setFactory({ name: String(org.name ?? "Factory"), address: String(org.factory_address ?? ""), latitude: org.factory_latitude == null ? null : Number(org.factory_latitude), longitude: org.factory_longitude == null ? null : Number(org.factory_longitude), radiusM: Number(org.factory_geofence_radius_m ?? 250) });
        }
      }
    }
    // Fetch immediately on entry so the fleet map is not blank/stale for the first 12 seconds.
    void refreshLocations();
    const interval = window.setInterval(() => void refreshLocations(), 12000);
    // Authorized clients receive truck changes through Supabase Realtime (RLS still applies).
    // The polling refresh remains as a recovery path for dropped WebSocket connections.
    const channel = supabase.channel("supplyos-fleet-live-trucks")
      .on("postgres_changes", { event: "UPDATE", schema: "public", table: "dispatch_trucks" }, (payload) => {
        const row = payload.new as unknown as TruckRow;
        if (!row?.id) return;
        const updatedTruck = fromTruckRow(row);
        setTrucks(current => current.map(truck => truck.id === updatedTruck.id ? updatedTruck : truck));
        setRoutes(current => current.map(route => route.truck?.id === updatedTruck.id ? { ...route, truck: updatedTruck } : route));
        setCoordinates(current => ({ ...current, [updatedTruck.id]: { lat: updatedTruck.latitude == null ? "" : String(updatedTruck.latitude), lng: updatedTruck.longitude == null ? "" : String(updatedTruck.longitude) } }));
        setLastRefreshAt(new Date().toISOString());
      })
      .on("postgres_changes", { event: "*", schema: "public", table: "employee_location_sessions" }, (payload) => {
        const row = (payload.new ?? payload.old) as unknown as Record<string, unknown>;
        if (!row?.id) return;
        if (row.ended_at) { setEmployees(current => current.filter(employee => employee.id !== String(row.id))); return; }
        setEmployees(current => {
          const updatedEmployee: EmployeeLocation = {
            id: String(row.id), userId: String(row.user_id), employeeName: String(row.employee_name ?? "Employee"),
            latitude: row.current_latitude == null ? null : Number(row.current_latitude), longitude: row.current_longitude == null ? null : Number(row.current_longitude),
            locationUpdatedAt: row.last_location_at == null ? null : String(row.last_location_at), accuracyM: row.current_location_accuracy_m == null ? null : Number(row.current_location_accuracy_m),
            distanceM: row.factory_distance_m == null ? null : Number(row.factory_distance_m), geofenceState: String(row.factory_geofence_state ?? "unknown"), startedAt: String(row.started_at),
          };
          return [updatedEmployee, ...current.filter(employee => employee.id !== updatedEmployee.id)];
        });
        setLastRefreshAt(new Date().toISOString());
      }).subscribe();
    return () => { mountedRef.current = false; window.clearInterval(interval); void supabase.removeChannel(channel); };
  }, []);

  useEffect(() => () => {
    mountedRef.current = false;
    if (watchIdRef.current !== null && typeof navigator !== "undefined" && navigator.geolocation) navigator.geolocation.clearWatch(watchIdRef.current);
  }, []);

  async function saveTruckLocation(truckId: string) {
    const point = coordinates[truckId];
    if (!point || !point.lat.trim() || !point.lng.trim()) { setNotice({ ok: false, text: "Enter the truck's latitude and longitude first." }); return; }
    const latitude = Number(point.lat); const longitude = Number(point.lng);
    if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90 || !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
      setNotice({ ok: false, text: "Latitude must be −90 to 90 and longitude −180 to 180." }); return;
    }
    setBusy(`location:${truckId}`); setNotice(null);
    const result = await runDispatchCommand("update_location", { truck_id: truckId, latitude, longitude });
    setBusy(null); setNotice({ ok: result.ok, text: result.message });
    if (result.ok) {
      const data = result.data ?? {};
      const states = Array.isArray(data.geofence_states) ? data.geofence_states as Array<Record<string, unknown>> : [];
      const stateByKey = new Map(states.map(state => [String(state.load_id) + ":" + String(state.booking_id), state]));
      const position = (data.truck_position ?? {}) as Record<string, unknown>;
      const timestamp = String(position.location_updated_at ?? data.location_updated_at ?? new Date().toISOString());
      const positionPatch = { latitude, longitude, locationUpdatedAt: timestamp,
        factoryDistanceM: position.factory_distance_m == null ? null : Number(position.factory_distance_m),
        factoryGeofenceState: String(position.factory_geofence_state ?? "unknown"),
        factoryGeofenceCheckedAt: position.factory_geofence_checked_at == null ? null : String(position.factory_geofence_checked_at),
        locationSource: String(position.location_source ?? "manual"), locationAccuracyM: position.current_location_accuracy_m == null ? null : Number(position.current_location_accuracy_m) };
      setTrucks(current => current.map(truck => truck.id === truckId ? { ...truck, ...positionPatch } : truck));
      setRoutes(current => current.map(route => route.truck?.id === truckId ? {
        ...route, truck: { ...route.truck!, ...positionPatch },
        stops: route.stops.map(stop => { const state = stateByKey.get(route.id + ":" + stop.bookingId); return state ? { ...stop, geofenceState: String(state.state), distanceM: state.distance_m == null ? null : Number(state.distance_m), geofenceLastCheckedAt: state.last_checked_at == null ? null : String(state.last_checked_at) } : stop; }),
      } : route));
      setLastGpsSentAt(timestamp);
    }
  }

  function stopGpsSharing() {
    if (watchIdRef.current !== null && navigator.geolocation) navigator.geolocation.clearWatch(watchIdRef.current);
    watchIdRef.current = null; gpsSendingRef.current = false; setGpsSharing(false);
    setNotice({ ok: true, text: "Live GPS sharing stopped. The last recorded truck position remains visible." });
  }

  function startGpsSharing() {
    if (!gpsTruckId) { setNotice({ ok: false, text: "Select the truck this phone/device is travelling with." }); return; }
    if (!navigator.geolocation) { setNotice({ ok: false, text: "This browser does not support GPS location reporting." }); return; }
    if (watchIdRef.current !== null) navigator.geolocation.clearWatch(watchIdRef.current);
    lastGpsSendMsRef.current = 0; gpsSendingRef.current = false; setGpsSharing(true); setLastGpsSentAt(null);
    setNotice({ ok: true, text: "Waiting for a GPS fix. Keep this page open on the phone/device carried by the selected truck." });
    watchIdRef.current = navigator.geolocation.watchPosition(position => {
      const now = Date.now();
      if (gpsSendingRef.current || now - lastGpsSendMsRef.current < 10000) return;
      gpsSendingRef.current = true; lastGpsSendMsRef.current = now;
      const latitude = position.coords.latitude; const longitude = position.coords.longitude;
      void runDispatchCommand("update_gps_location", {
        truck_id: gpsTruckId,
        latitude,
        longitude,
        accuracy_m: position.coords.accuracy,
        recorded_at: new Date(position.timestamp).toISOString(),
      }).then(result => {
        gpsSendingRef.current = false;
        if (!mountedRef.current) return;
        if (!result.ok) { setNotice({ ok: false, text: `GPS update failed: ${result.message}` }); return; }
        const data = result.data ?? {};
        const position = (data.truck_position ?? {}) as Record<string, unknown>;
        const timestamp = String(position.location_updated_at ?? data.location_updated_at ?? new Date().toISOString());
        const states = Array.isArray(data.geofence_states) ? data.geofence_states as Array<Record<string, unknown>> : [];
        const stateByKey = new Map(states.map(state => [String(state.load_id) + ":" + String(state.booking_id), state]));
        const positionPatch = { latitude, longitude, locationUpdatedAt: timestamp,
          factoryDistanceM: position.factory_distance_m == null ? null : Number(position.factory_distance_m),
          factoryGeofenceState: String(position.factory_geofence_state ?? "unknown"),
          factoryGeofenceCheckedAt: position.factory_geofence_checked_at == null ? null : String(position.factory_geofence_checked_at),
          locationSource: String(position.location_source ?? "manual"), locationAccuracyM: position.current_location_accuracy_m == null ? null : Number(position.current_location_accuracy_m) };
        setCoordinates(current => ({ ...current, [gpsTruckId]: { lat: latitude.toFixed(6), lng: longitude.toFixed(6) } }));
        setTrucks(current => current.map(truck => truck.id === gpsTruckId ? { ...truck, ...positionPatch } : truck));
        setRoutes(current => current.map(route => route.truck?.id === gpsTruckId ? { ...route, truck: { ...route.truck!, ...positionPatch },
          stops: route.stops.map(stop => { const state = stateByKey.get(route.id + ":" + stop.bookingId); return state ? { ...stop, geofenceState: String(state.state), distanceM: state.distance_m == null ? null : Number(state.distance_m), geofenceLastCheckedAt: state.last_checked_at == null ? null : String(state.last_checked_at) } : stop; }) } : route));
        setLastGpsSentAt(timestamp);
        const trusted = data.trusted_for_geofences === true;
        setNotice({ ok: trusted, text: `${result.message} Live GPS sharing continues for ${trucks.find(truck => truck.id === gpsTruckId)?.registrationNo ?? "the selected truck"} while the device reports positions about every 10 seconds.` });
      }).catch(() => {
        gpsSendingRef.current = false;
        if (mountedRef.current) setNotice({ ok: false, text: "GPS update could not reach SupplyOS. Check the connection and keep the page open." });
      });
    }, error => {
      if (!mountedRef.current) return;
      const message = error.code === error.PERMISSION_DENIED ? "GPS permission was denied. Allow location access in the browser and start sharing again." : error.code === error.POSITION_UNAVAILABLE ? "The device cannot determine its position. Check GPS and network availability." : "GPS timed out waiting for a position. Keep the browser open and retry if necessary.";
      setNotice({ ok: false, text: message }); setGpsSharing(false);
      if (watchIdRef.current !== null) navigator.geolocation.clearWatch(watchIdRef.current);
      watchIdRef.current = null;
    }, { enableHighAccuracy: true, maximumAge: 5000, timeout: 20000 });
  }

  async function saveFactoryGeofence(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const latitude = Number(factoryLat); const longitude = Number(factoryLng); const radius = Number(factoryRadius);
    if (!factoryLat.trim() || !factoryLng.trim() || !Number.isFinite(latitude) || latitude < -90 || latitude > 90 || !Number.isFinite(longitude) || longitude < -180 || longitude > 180 || !Number.isInteger(radius) || radius < 25 || radius > 10000) {
      setNotice({ ok: false, text: "Enter valid coordinates and choose a geofence radius from 25 to 10,000 metres." }); return;
    }
    setBusy("factory"); setNotice(null);
    const result = await runDispatchCommand("set_factory_geofence", { latitude, longitude, address: factoryAddress, radius_m: radius });
    setBusy(null); setNotice({ ok: result.ok, text: result.message });
    if (result.ok) {
      const saved: Record<string, unknown> = result.data ?? {};
      const savedLatitude = Number(saved.factory_latitude ?? latitude);
      const savedLongitude = Number(saved.factory_longitude ?? longitude);
      const savedRadius = Number(saved.factory_geofence_radius_m ?? radius);
      const savedAddress = String(saved.factory_address ?? factoryAddress);
      setFactory({ name: factory?.name ?? "Factory", address: savedAddress, latitude: savedLatitude, longitude: savedLongitude, radiusM: savedRadius });
      setFactoryLat(String(savedLatitude));
      setFactoryLng(String(savedLongitude));
      setFactoryAddress(savedAddress);
      setFactoryRadius(String(savedRadius));
    }
  }

  async function stopEmployeeShift(sessionId: string) {
    if (!window.confirm("Stop this employee's active location-sharing session? The phone will stop being tracked by this shift session when its next background update is rejected; ask the employee to also tap End shift on the phone.")) return;
    setBusy(`employee:${sessionId}`); setNotice(null);
    const { data, error } = await createClient().rpc("admin_stop_employee_location_shift", { p_session_id: sessionId, p_reason: "manager_stopped" });
    setBusy(null);
    if (error || !(data as { stopped?: boolean } | null)?.stopped) { setNotice({ ok: false, text: error?.message ?? "Could not stop the employee session." }); return; }
    setEmployees(current => current.filter(employee => employee.id !== sessionId));
    setNotice({ ok: true, text: "Employee shift session ended on the server. Ask the employee to reopen SupplyOS if the phone's location service needs to be stopped immediately." });
  }

  async function saveRadius(loadId: string) {
    const radius = Number(radii[loadId]);
    setBusy(`radius:${loadId}`); setNotice(null);
    const result = await runDispatchCommand("set_geofence_radius", { load_id: loadId, radius_m: radius });
    setBusy(null); setNotice({ ok: result.ok, text: result.message });
    if (result.ok) setRoutes(current => current.map(route => route.id === loadId ? { ...route, radiusM: radius } : route));
  }

  const openIncidents = incidents.filter(incident => incident.status === "open");
  const mappedStops = routes.reduce((sum, route) => sum + route.stops.filter(stop => stop.latitude !== null && stop.longitude !== null).length, 0);
  const checkedStops = routes.reduce((sum, route) => sum + route.stops.filter(stop => stop.geofenceState && stop.geofenceState !== "not_checked").length, 0);
  const insideStops = routes.reduce((sum, route) => sum + route.stops.filter(stop => stop.geofenceState === "inside").length, 0);
  const nearbyStops = routes.reduce((sum, route) => sum + route.stops.filter(stop => stop.geofenceState === "nearby").length, 0);
  const liveGpsCount = trucks.filter(truck => truck.locationUpdatedAt && Date.now() - new Date(truck.locationUpdatedAt).getTime() <= 120000 && ["phone_gps", "hardware_gps"].includes(truck.locationSource ?? "")).length;
  const atFactoryCount = trucks.filter(truck => truck.factoryGeofenceState === "inside").length;
  const selectedGpsTruck = trucks.find(truck => truck.id === gpsTruckId) ?? null;

  return <div className="page-stack route-page">
    <div className="page-heading-row"><div><div className="eyebrow">OPERATIONS / FLEET VISIBILITY</div><h1>Routes & geofencing</h1><p>Live truck and employee visibility with one shared factory gate geofence, stale-position warnings, and delivery-stop arrival zones.</p></div><div className="heading-actions"><span className="route-live-status"><i/> Realtime updates · 12 sec fallback</span><a className="button button-secondary" href="/dispatch"><Truck size={15}/> Open dispatch</a></div></div>
    {notice && <div className={`dispatch-inline-status ${notice.ok ? "success" : "error"}`}>{notice.ok ? <CheckCircle2 size={16}/> : <AlertTriangle size={16}/>}<span>{notice.text}</span></div>}
    <div className="dispatch-metric-grid">
      <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-blue"><Truck size={17}/></span><span className="metric-trend">Whole fleet</span></div><div className="metric-value">{trucks.length}</div><div className="metric-label">Registered trucks on map/list</div></div>
      <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-green"><Radio size={17}/></span><span className="metric-trend">Fresh GPS</span></div><div className="metric-value">{liveGpsCount}</div><div className="metric-label">Positions updated in last 2 minutes</div></div>
      <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-violet"><MapPin size={17}/></span><span className="metric-trend">Factory geofence</span></div><div className="metric-value">{atFactoryCount}</div><div className="metric-label">Trucks inside the factory radius</div></div>
      <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-amber"><AlertTriangle size={17}/></span><span className="metric-trend">Needs attention</span></div><div className="metric-value">{openIncidents.length}</div><div className="metric-label">Open route incidents</div></div>
    </div>
    <div className="route-geofence-summary"><span><strong>{checkedStops}</strong> delivery-stop checks recorded</span><span><strong>{insideStops}</strong> customer-stop geofences currently inside</span><span><strong>{nearbyStops}</strong> customer stops near geofence edge</span><span><strong>{mappedStops}</strong> customer pins available</span></div>

    <div className="route-console-grid">
      <RouteMap routes={routes} trucks={trucks} factory={factory} employees={employees}/>
      <section className="panel route-factory-panel"><div className="panel-heading"><div><h2>Factory base geofence</h2><p>One factory reference point for every truck. Set this to the dispatch gate—not a customer location.</p></div><span className="panel-heading-icon"><MapPinned size={17}/></span></div>
        <form className="route-factory-form" onSubmit={event => void saveFactoryGeofence(event)}>
          <label>Factory / gate address<input value={factoryAddress} maxLength={300} onChange={event => setFactoryAddress(event.target.value)} placeholder="Factory gate address, industrial area"/></label>
          <div className="route-factory-coordinate-grid"><label>Latitude<input inputMode="decimal" required value={factoryLat} onChange={event => setFactoryLat(event.target.value)} placeholder="e.g. 32.1877"/></label><label>Longitude<input inputMode="decimal" required value={factoryLng} onChange={event => setFactoryLng(event.target.value)} placeholder="e.g. 74.1945"/></label></div>
          <label>Gate geofence radius<select value={factoryRadius} onChange={event => setFactoryRadius(event.target.value)}><option value="100">100 m</option><option value="250">250 m</option><option value="500">500 m</option><option value="1000">1 km</option><option value="2000">2 km</option></select></label>
          <button type="submit" className="button button-primary" disabled={busy === "factory"}>{busy === "factory" ? <span className="dispatch-spinner"/> : <Save size={15}/>} Save shared factory geofence</button>
        </form>
        <div className="route-factory-note"><strong>One source of truth.</strong> Each GPS update recalculates every truck’s distance to this factory and classifies it as inside the configured radius, nearby (next 500 m), or outside. A location is considered fresh for 2 minutes.</div>
      </section>
    </div>

    {canManageEmployeeLocations && <section className="panel"><div className="panel-heading"><div><h2>Employee activity · live geofence</h2><p>Shows only employees who explicitly started a work-shift location session. Positions older than 2 minutes are stale; ending a shift removes it from the active map.</p></div><span className="table-count">{employees.length} active shifts</span></div>
      {employees.length ? <div className="route-truck-location-grid">{employees.map(employee => {
        const fresh = !!employee.locationUpdatedAt && Date.now() - new Date(employee.locationUpdatedAt).getTime() <= 120000;
        const state = employee.geofenceState || "unknown";
        return <article className="route-truck-location-card" key={employee.id}><div className="route-truck-location-title"><span className="truck-mini-icon"><LocateFixed size={16}/></span><div><strong>{employee.employeeName}</strong><small>Work shift started {new Date(employee.startedAt).toLocaleString()}</small></div><span className={`route-geofence-state route-geofence-state-${fresh ? state : "unknown"}`}>{fresh ? state.replaceAll("_", " ") : "stale"}</span></div>
          <div className="route-truck-return-distance"><span>Distance from factory gate</span><strong>{formatDistance(employee.distanceM)}</strong><small>{fresh ? `Live phone GPS · ${employee.accuracyM == null ? "accuracy unknown" : `${Math.round(employee.accuracyM)} m accuracy`}` : employee.locationUpdatedAt ? `Last position ${new Date(employee.locationUpdatedAt).toLocaleString()} · stale` : "Waiting for first GPS fix"}</small></div>
          <button type="button" className="button button-secondary button-small" disabled={busy === `employee:${employee.id}`} onClick={() => void stopEmployeeShift(employee.id)}>{busy === `employee:${employee.id}` ? <span className="dispatch-spinner"/> : <Square size={13}/>} End server session</button>
        </article>;
      })}</div> : <div className="empty-table"><div className="empty-table-icon"><LocateFixed size={20}/></div><strong>No active employee location sessions</strong><p>Install the SupplyOS Employee app on a company phone, sign in with the employee's own account, and have them explicitly start a shift. The map will update once the phone sends its first GPS fix.</p></div>}
    </section>}

    <section className="panel route-live-gps-panel"><div className="panel-heading"><div><h2>Live GPS sharing</h2><p>Open this page on a phone or GPS-enabled device that travels with the selected truck. The driver/device must grant location permission.</p></div><span className="panel-heading-icon"><LocateFixed size={17}/></span></div>
      <div className="route-gps-share-controls"><label>Truck/device pairing<select value={gpsTruckId} disabled={gpsSharing} onChange={event => setGpsTruckId(event.target.value)}><option value="">Select a truck</option>{trucks.map(truck => <option key={truck.id} value={truck.id}>{truck.registrationNo} · {truck.name}</option>)}</select></label>
        <div className="route-gps-selected"><strong>{selectedGpsTruck?.registrationNo ?? "No truck selected"}</strong><span>{selectedGpsTruck?.driverName || "Driver not set"} · {selectedGpsTruck?.status.replaceAll("_", " ") ?? "—"}</span><small>{selectedGpsTruck?.locationUpdatedAt ? `Last position ${new Date(selectedGpsTruck.locationUpdatedAt).toLocaleString()}` : "No position received"}</small></div>
        {gpsSharing ? <button type="button" className="button button-secondary" onClick={stopGpsSharing}><Square size={14}/> Stop live sharing</button> : <button type="button" className="button button-primary" disabled={!gpsTruckId} onClick={startGpsSharing}><LocateFixed size={15}/> Start live GPS</button>}
      </div>
      <p className="route-gps-footnote">While this page stays open and the browser provides GPS, SupplyOS sends coordinates roughly every 10 seconds. Mobile browsers may pause location when the screen locks or the page goes into the background; continuous background tracking requires a dedicated driver app/telematics device. Latest UI refresh: {new Date(lastRefreshAt).toLocaleTimeString()} {lastGpsSentAt ? `· last GPS send: ${new Date(lastGpsSentAt).toLocaleTimeString()}` : ""}</p>
    </section>

    <section className="panel"><div className="panel-heading"><div><h2>Full fleet · distance back to factory</h2><p>All trucks are listed whether on a delivery route, waiting, in maintenance or inactive.</p></div><span className="table-count">{trucks.length} vehicles</span></div>
      <div className="route-truck-location-grid">{trucks.map(truck => {
        const distance = factoryDistance(truck, factory);
        const positionAgeMs = truck.locationUpdatedAt ? Date.now() - new Date(truck.locationUpdatedAt).getTime() : Number.POSITIVE_INFINITY;
        const fresh = positionAgeMs >= 0 && positionAgeMs <= 120000
          && ["phone_gps", "hardware_gps"].includes(truck.locationSource ?? "")
          && truck.locationAccuracyM != null && truck.locationAccuracyM <= 150;
        const state = fresh ? truck.factoryGeofenceState ?? "unknown" : "unknown";
        return <article className="route-truck-location-card" key={truck.id}><div className="route-truck-location-title"><span className="truck-mini-icon"><Truck size={16}/></span><div><strong>{truck.registrationNo}</strong><small>{truck.name} · {truck.driverName || "Driver not set"}</small></div><span className={`route-geofence-state route-geofence-state-${state}`}>{state.replaceAll("_", " ")}</span></div>
          <div className="route-truck-return-distance"><span>Straight-line distance from latest coordinates to factory</span><strong>{formatDistance(distance)}</strong><small>{fresh ? `Live GPS · ${Math.round(truck.locationAccuracyM!)} m accuracy` : truck.locationSource === "manual" && truck.locationUpdatedAt ? `Manual / unverified · ${new Date(truck.locationUpdatedAt).toLocaleString()}` : truck.locationUpdatedAt && truck.locationAccuracyM != null && truck.locationAccuracyM > 150 ? `Low GPS accuracy (${Math.round(truck.locationAccuracyM)} m) · unverified` : truck.locationUpdatedAt ? `Stale or untrusted GPS · ${new Date(truck.locationUpdatedAt).toLocaleString()}` : "No GPS report"}</small></div>
          <div className="route-coordinates"><label><span className="sr-only">Latitude</span><input inputMode="decimal" aria-label={`${truck.registrationNo} latitude`} placeholder="Latitude" value={coordinates[truck.id]?.lat ?? ""} onChange={event => setCoordinates(current => ({ ...current, [truck.id]: { lat: event.target.value, lng: current[truck.id]?.lng ?? "" } }))}/></label><label><span className="sr-only">Longitude</span><input inputMode="decimal" aria-label={`${truck.registrationNo} longitude`} placeholder="Longitude" value={coordinates[truck.id]?.lng ?? ""} onChange={event => setCoordinates(current => ({ ...current, [truck.id]: { lat: current[truck.id]?.lat ?? "", lng: event.target.value } }))}/></label><button type="button" className="button button-secondary button-small" disabled={busy === `location:${truck.id}`} onClick={() => void saveTruckLocation(truck.id)}>{busy === `location:${truck.id}` ? <span className="dispatch-spinner"/> : <Navigation size={13}/>} Manual update</button></div>
        </article>;
      })}{!trucks.length && <p className="muted">No fleet vehicles registered yet. Add vehicles in Dispatch → Trucks.</p>}</div>
    </section>

    <section className="panel"><div className="panel-heading"><div><h2>Routes and customer stops</h2><p>Delivery geofences use each customer’s saved coordinates; the factory geofence remains separate and shared by all vehicles.</p></div><span className="table-count">{routes.length} active routes</span></div>
      <div className="route-list">{routes.map(route => <article className="route-load-card" key={route.id}>
        <div className="route-card-heading"><div><h3>{route.loadNo}</h3><p>{route.truck?.registrationNo ?? "Truck not assigned"} · {route.status.replaceAll("_", " ")}</p></div><span className={`dispatch-status ${route.status === "in_transit" ? "dispatch-status-transit" : "dispatch-status-planned"}`}>{route.status.replaceAll("_", " ")}</span></div>
        {route.stops.map((stop,index) => {
          const gpsTimestamp = route.truck?.locationUpdatedAt ? new Date(route.truck.locationUpdatedAt).getTime() : 0;
          const gpsTrusted = !!route.truck && gpsTimestamp > 0 && Date.now() - gpsTimestamp <= 120000
            && ["phone_gps", "hardware_gps"].includes(route.truck.locationSource ?? "")
            && route.truck.locationAccuracyM != null && route.truck.locationAccuracyM <= 150;
          const shownState = gpsTrusted ? stop.geofenceState : "unknown";
          const stateLabel = !gpsTrusted
            ? (!route.truck ? "No truck assigned — arrival unverified" : !gpsTimestamp ? "Waiting for a trusted GPS fix — arrival unverified" : Date.now() - gpsTimestamp > 120000 ? "Location stale — arrival unverified" : route.truck.locationSource === "manual" ? "Manual coordinates — arrival unverified" : "GPS accuracy unavailable/too low — arrival unverified")
            : stop.geofenceState === "inside" ? "Inside delivery geofence" : stop.geofenceState === "nearby" ? "Near delivery geofence edge" : stop.geofenceState === "outside" ? "Outside delivery geofence" : "No delivery geofence report yet";
          return <div className="route-stop" key={stop.bookingId}><span className="route-stop-index">{index+1}</span><div><address>{stop.customerName} · {stop.bookingNo}</address><small>{[stop.address,stop.city,stop.province].filter(Boolean).join(", ") || "Shop address not set"}</small>{stop.phone && <small>{stop.phone}</small>}<small className={`route-geofence-state route-geofence-state-${shownState || "not_checked"}`}>{stateLabel}{gpsTrusted && stop.distanceM != null ? ` · ${Math.round(stop.distanceM)} m from customer pin` : ""}</small>{stop.latitude == null || stop.longitude == null ? <small className="route-coordinate-warning">Coordinates missing — map pin unavailable</small> : <small className={stop.customerCode.startsWith("DEMO-CUST-") ? "route-coordinate-warning" : "route-coordinate-success"}>{Number(stop.latitude).toFixed(5)}, {Number(stop.longitude).toFixed(5)}{stop.customerCode.startsWith("DEMO-CUST-") ? " · approximate demo pin" : ""}</small>}</div></div>;
        })}
        <div className="route-geofence-control"><label>Customer geofence radius <select aria-label={`Geofence radius for ${route.loadNo}`} value={radii[route.id] ?? String(route.radiusM)} onChange={event => setRadii(current => ({ ...current, [route.id]: event.target.value }))}><option value="100">100 m</option><option value="250">250 m</option><option value="500">500 m</option><option value="1000">1 km</option><option value="2000">2 km</option></select></label><button className="button button-secondary button-small" type="button" disabled={busy === `radius:${route.id}`} onClick={() => void saveRadius(route.id)}>{busy === `radius:${route.id}` ? <span className="dispatch-spinner"/> : <RefreshCw size={13}/>} Save customer radius</button></div>
      </article>)}{!routes.length && <div className="empty-table"><div className="empty-table-icon"><RouteIcon size={20}/></div><strong>No active routes yet</strong><p>Plan loads and assign trucks in Dispatch. Route stops appear here while planned, ready or in transit.</p></div>}</div>
    </section>

    <section className="panel"><div className="panel-heading"><div><h2>Route incidents</h2><p>Contingencies reported against a load appear here.</p></div><span className="table-count">{openIncidents.length} open</span></div>
      {openIncidents.length ? <div className="dispatch-contingency-list">{openIncidents.map(incident => <article className="dispatch-contingency-item" key={incident.id}><div><span className={`contingency-severity contingency-severity-${incident.severity}`}>{incident.severity} · {incident.issue_type.replaceAll("_", " ")}</span><strong>{incident.summary}</strong><p>{one(incident.dispatch_loads)?.load_no ?? "Route load"} · {new Date(incident.created_at).toLocaleString()}</p></div><a className="button button-secondary button-small" href="/dispatch?tab=incidents">Manage incidents</a></article>)}</div> : <div className="dispatch-all-clear"><span><CheckCircle2 size={23}/></span><strong>No open route incidents</strong><p>Breakdowns, road closures, delays and other incidents reported in Dispatch will be surfaced here.</p></div>}
    </section>
  </div>;
}
