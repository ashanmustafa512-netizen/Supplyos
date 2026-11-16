"use client";

import { useEffect, useRef, useState } from "react";
import { Activity, MapPinned, RotateCw } from "lucide-react";
import { createClient } from "@/lib/supabase/client";

export type TeamLocation = {
  id: string;
  userId: string;
  name: string;
  role: "manager" | "staff" | string;
  latitude: number | null;
  longitude: number | null;
  lastLocationAt: string | null;
  accuracyM: number | null;
  distanceM: number | null;
  geofenceState: string;
  startedAt: string;
};

type FactoryLocation = { name: string; latitude: number | null; longitude: number | null; radiusM: number };

type LeafletPoint = [number, number];
type LeafletLayer = { addTo(map: LeafletMap | LeafletLayerGroup): LeafletLayer; bindPopup(content: string): LeafletLayer };
type LeafletLayerGroup = { addTo(map: LeafletMap): LeafletLayerGroup; clearLayers(): void };
type LeafletMap = { setView(center: LeafletPoint, zoom: number): LeafletMap; fitBounds(bounds: unknown, options?: object): LeafletMap; remove(): void; invalidateSize(): void };
type LeafletApi = {
  map(container: HTMLElement, options?: object): LeafletMap;
  tileLayer(url: string, options?: object): LeafletLayer;
  marker(position: LeafletPoint, options?: object): LeafletLayer;
  circle(position: LeafletPoint, options?: object): LeafletLayer;
  layerGroup(): LeafletLayerGroup;
  latLngBounds(points: LeafletPoint[]): unknown;
};
declare global { interface Window { L?: LeafletApi } }

const leafletCss = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css";
const leafletScript = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js";

function loadLeaflet(): Promise<LeafletApi> {
  if (window.L) return Promise.resolve(window.L);
  return new Promise((resolve, reject) => {
    let script = document.querySelector<HTMLScriptElement>('script[data-supplyos-leaflet="true"]');
    if (!document.querySelector(`link[href="${leafletCss}"]`)) {
      const link = document.createElement("link");
      link.rel = "stylesheet";
      link.href = leafletCss;
      link.dataset.supplyosLeaflet = "true";
      document.head.appendChild(link);
    }
    if (!script) {
      script = document.createElement("script");
      script.src = leafletScript;
      script.async = true;
      script.dataset.supplyosLeaflet = "true";
      document.head.appendChild(script);
    }
    script.addEventListener("load", () => window.L ? resolve(window.L) : reject(new Error("The map library loaded without its API.")), { once: true });
    script.addEventListener("error", () => reject(new Error("Could not load the map library. Check your connection and content blocker.")), { once: true });
  });
}

function escapeHtml(value: string) {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#039;");
}

function freshness(location: TeamLocation) {
  if (!location.lastLocationAt) return "Waiting for first GPS fix";
  return Date.now() - new Date(location.lastLocationAt).getTime() <= 120000 ? "Live" : "Stale · last known position";
}

export function TeamLocationMap({
  organizationId,
  initialLocations,
  factory,
}: {
  organizationId: string;
  initialLocations: TeamLocation[];
  factory: FactoryLocation | null;
}) {
  const mapElement = useRef<HTMLDivElement>(null);
  const mapRef = useRef<LeafletMap | null>(null);
  const layerRef = useRef<LeafletLayerGroup | null>(null);
  const fittedRef = useRef(false);
  const mountedRef = useRef(false);
  const [locations, setLocations] = useState(initialLocations);
  const [mapError, setMapError] = useState("");
  const [mapReady, setMapReady] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [lastRefresh, setLastRefresh] = useState<string | null>(null);

  useEffect(() => {
    mountedRef.current = true;
    const supabase = createClient();
    let requestInFlight = false;

    async function refreshLocations() {
      if (!mountedRef.current || requestInFlight || document.visibilityState !== "visible") return;
      requestInFlight = true;
      setRefreshing(true);
      try {
        const { data, error } = await supabase
          .from("employee_location_sessions")
          .select("id,user_id,employee_name,current_latitude,current_longitude,last_location_at,current_location_accuracy_m,factory_distance_m,factory_geofence_state,started_at")
          .eq("organization_id", organizationId)
          .is("ended_at", null)
          .order("last_location_at", { ascending: false })
          .limit(500);
        if (error) throw error;
        if (!mountedRef.current) return;
        const rows = (data ?? []) as unknown as Array<Record<string, unknown>>;
        const userIds = [...new Set(rows.map(row => String(row.user_id)))];
        const { data: membershipRows } = userIds.length
          ? await supabase.from("memberships").select("user_id,role").eq("organization_id", organizationId).in("user_id", userIds)
          : { data: [] as Array<{ user_id: string; role: string }> };
        const roleByUser = new Map((membershipRows ?? []).map(row => [row.user_id, row.role]));
        if (!mountedRef.current) return;
        setLocations(rows.map(row => ({
          id: String(row.id),
          userId: String(row.user_id),
          name: String(row.employee_name ?? "Team member"),
          role: roleByUser.get(String(row.user_id)) ?? "staff",
          latitude: row.current_latitude == null ? null : Number(row.current_latitude),
          longitude: row.current_longitude == null ? null : Number(row.current_longitude),
          lastLocationAt: row.last_location_at == null ? null : String(row.last_location_at),
          accuracyM: row.current_location_accuracy_m == null ? null : Number(row.current_location_accuracy_m),
          distanceM: row.factory_distance_m == null ? null : Number(row.factory_distance_m),
          geofenceState: String(row.factory_geofence_state ?? "unknown"),
          startedAt: String(row.started_at),
        })));
        setLastRefresh(new Date().toISOString());
      } catch (error) {
        if (mountedRef.current) setMapError(error instanceof Error ? error.message : "Could not refresh team locations.");
      } finally {
        requestInFlight = false;
        if (mountedRef.current) setRefreshing(false);
      }
    }

    void refreshLocations();
    const interval = window.setInterval(() => void refreshLocations(), 30000);
    const onVisibility = () => { if (document.visibilityState === "visible") void refreshLocations(); };
    document.addEventListener("visibilitychange", onVisibility);
    const channel = supabase
      .channel(`supplyos-team-locations-${organizationId}`)
      .on("postgres_changes", {
        event: "*",
        schema: "public",
        table: "employee_location_sessions",
        filter: `organization_id=eq.${organizationId}`,
      }, () => { void refreshLocations(); })
      .subscribe();

    return () => {
      mountedRef.current = false;
      window.clearInterval(interval);
      document.removeEventListener("visibilitychange", onVisibility);
      void supabase.removeChannel(channel);
    };
  }, [organizationId]);

  useEffect(() => {
    let cancelled = false;
    let map: LeafletMap | null = null;
    loadLeaflet().then(L => {
      if (cancelled || !mapElement.current) return;
      map = L.map(mapElement.current, { scrollWheelZoom: true, zoomControl: true })
        .setView([30.3753, 69.3451], 5);
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        maxZoom: 19,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      }).addTo(map);
      mapRef.current = map;
      layerRef.current = L.layerGroup().addTo(map);
      setMapError("");
      setMapReady(true);
      window.setTimeout(() => map?.invalidateSize(), 100);
    }).catch(error => {
      if (!cancelled) setMapError(error instanceof Error ? error.message : "Map could not be loaded.");
    });
    return () => {
      cancelled = true;
      map?.remove();
      mapRef.current = null;
      layerRef.current = null;
    };
  }, []);

  useEffect(() => {
    const L = window.L;
    const map = mapRef.current;
    const layer = layerRef.current;
    if (!mapReady || !L || !map || !layer) return;
    layer.clearLayers();
    const points: LeafletPoint[] = [];

    if (factory?.latitude != null && factory.longitude != null) {
      const factoryPoint: LeafletPoint = [factory.latitude, factory.longitude];
      points.push(factoryPoint);
      L.circle(factoryPoint, {
        radius: factory.radiusM || 250,
        color: "#15936d",
        fillColor: "#32b98d",
        fillOpacity: 0.12,
        weight: 2,
      }).addTo(layer);
      L.marker(factoryPoint).addTo(layer).bindPopup(
        `<strong>${escapeHtml(factory.name)}</strong><br>Factory geofence: ${factory.radiusM} m`
      );
    }

    locations.forEach(person => {
      if (person.latitude == null || person.longitude == null) return;
      const point: LeafletPoint = [person.latitude, person.longitude];
      points.push(point);
      const isFresh = freshness(person) === "Live";
      const state = person.geofenceState || "unknown";
      const markerColor = !isFresh ? "#d97706"
        : state === "inside" ? "#15803d"
        : state === "nearby" ? "#ca8a04"
        : state === "outside" ? "#dc2626"
        : "#64748b";
      L.circle(point, {
        radius: Math.max(18, Math.min(person.accuracyM ?? 35, 150)),
        color: markerColor,
        fillColor: markerColor,
        fillOpacity: 0.25,
        weight: 2,
      }).addTo(layer);
      L.marker(point).addTo(layer).bindPopup(
        `<strong>${escapeHtml(person.name)}</strong><br>Role: ${escapeHtml(person.role)}<br>Status: ${isFresh ? "LIVE GPS" : "STALE / WAITING"}<br>Factory geofence: ${escapeHtml(state.replaceAll("_", " "))}<br>Distance from factory: ${person.distanceM == null ? "unknown" : `${Math.round(person.distanceM)} m`}<br>GPS accuracy: ${person.accuracyM == null ? "not reported" : `${Math.round(person.accuracyM)} m`}<br>Last update: ${escapeHtml(person.lastLocationAt ? new Date(person.lastLocationAt).toLocaleString() : "No GPS fix")}`
      );
    });

    if (!fittedRef.current && points.length > 1) {
      map.fitBounds(L.latLngBounds(points), { padding: [28, 28], maxZoom: 13 });
      fittedRef.current = true;
    } else if (!fittedRef.current && points.length === 1) {
      map.setView(points[0], 13);
      fittedRef.current = true;
    }
    window.setTimeout(() => map.invalidateSize(), 80);
  }, [locations, factory, mapReady]);

  const liveCount = locations.filter(location => freshness(location) === "Live").length;
  const staleCount = locations.length - liveCount;

  return (
    <div className="page-stack">
      <section className="metric-grid metric-grid-three">
        <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-green"><Activity size={17}/></span><span className="metric-trend">Active shifts</span></div><div className="metric-value">{locations.length}</div><div className="metric-label">Managers and employees currently sharing location</div></div>
        <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-blue"><MapPinned size={17}/></span><span className="metric-trend">Fresh GPS</span></div><div className="metric-value">{liveCount}</div><div className="metric-label">Updates received in the last 2 minutes</div></div>
        <div className="metric-card"><div className="metric-card-top"><span className="metric-icon metric-amber"><RotateCw size={17}/></span><span className="metric-trend">Stale / waiting</span></div><div className="metric-value">{staleCount}</div><div className="metric-label">Active shifts without a fresh GPS fix</div></div>
      </section>

      <section className="panel route-map-panel">
        <div className="panel-heading">
          <div><h2>Live team map</h2><p>Only active work-shift sessions are displayed. Stale markers show last known locations, not live positions.</p></div>
          <button type="button" className="button button-secondary button-small" onClick={() => {
            const event = new Event("visibilitychange");
            document.dispatchEvent(event);
          }} disabled={refreshing}><RotateCw size={14}/> {refreshing ? "Refreshing…" : "Refresh"}</button>
        </div>
        <div className="route-map-summary">
          <span>{liveCount} fresh GPS</span><span>{staleCount} stale / waiting</span><span>{factory ? "Factory geofence configured" : "Factory geofence not configured"}</span>
          <span>{lastRefresh ? `Last sync ${new Date(lastRefresh).toLocaleTimeString()}` : "Waiting for sync"}</span>
        </div>
        <div className="route-map-container" ref={mapElement} aria-label="Owner map of active manager and employee work-shift locations"/>
        {mapError && <div className="route-map-error">{mapError}</div>}
        {!mapError && !mapReady && <div className="route-map-loading"><span className="dispatch-spinner"/> Loading team map…</div>}
        {!locations.length && <div className="route-map-hint">No manager or employee work-shift sessions are active right now.</div>}
        <div className="route-map-legend"><span><i className="route-legend-dot" style={{background:"#15803d"}}/>Fresh GPS</span><span><i className="route-legend-dot" style={{background:"#d97706"}}/>Stale / waiting</span><span><i className="route-legend-dot" style={{background:"#15936d"}}/>Factory geofence</span></div>
      </section>

      <section className="panel">
        <div className="panel-heading"><div><h2>Active work shifts</h2><p>Last location receipt and geofence status for every active session.</p></div><span className="table-count">{locations.length} active</span></div>
        <div className="table-scroll">
          <table className="data-table"><thead><tr><th>Team member</th><th>Role</th><th>Location status</th><th>Factory geofence</th><th>GPS accuracy</th><th>Last update</th></tr></thead>
            <tbody>{locations.map(person => <tr key={person.id}>
              <td><strong>{person.name}</strong></td>
              <td>{person.role === "manager" ? "Manager" : "Employee"}</td>
              <td><span className={freshness(person) === "Live" ? "status-pill status-approved" : "status-pill status-pending_approval"}><i/>{freshness(person)}</span></td>
              <td>{person.geofenceState.replaceAll("_", " ")}</td>
              <td>{person.accuracyM == null ? "—" : `${Math.round(person.accuracyM)} m`}</td>
              <td>{person.lastLocationAt ? new Date(person.lastLocationAt).toLocaleString() : "Waiting for first GPS fix"}</td>
            </tr>)}
            {!locations.length && <tr><td colSpan={6}>No active work-shift locations.</td></tr>}</tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
