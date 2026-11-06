"use client";

import { useEffect, useRef, useState } from "react";
import { AlertTriangle, MapPinned, Navigation, RotateCw } from "lucide-react";

export type Stop = {
  bookingId: string; bookingNo: string; customerName: string; customerCode: string; address: string; city: string; province: string;
  latitude: number | null; longitude: number | null; phone: string; geofenceState?: string; distanceM?: number | null; geofenceLastCheckedAt?: string | null;
};
export type RouteTruck = {
  id: string; registrationNo: string; name: string; driverName: string; status: string; latitude: number | null; longitude: number | null;
  locationUpdatedAt: string | null; factoryDistanceM?: number | null; factoryGeofenceState?: string; factoryGeofenceCheckedAt?: string | null;
  currentCity?: string; capacityOrders?: number; capacityKg?: number; locationSource?: string; locationAccuracyM?: number | null;
};
export type RouteLoad = { id: string; loadNo: string; status: string; destinationSummary: string; radiusM: number; truck: RouteTruck | null; stops: Stop[] };
export type RouteFactory = { name: string; address: string; latitude: number | null; longitude: number | null; radiusM: number };
export type EmployeeLocation = {
  id: string; userId: string; employeeName: string; latitude: number | null; longitude: number | null;
  locationUpdatedAt: string | null; accuracyM: number | null; distanceM: number | null; geofenceState: string; startedAt: string;
};
type LeafletPoint = [number, number];
type LeafletLayer = { addTo(map: LeafletMap | LeafletLayerGroup): LeafletLayer; bindPopup(content: string): LeafletLayer };
type LeafletLayerGroup = { addTo(map: LeafletMap): LeafletLayerGroup; clearLayers(): void };
type LeafletMap = { setView(center: LeafletPoint, zoom: number): LeafletMap; fitBounds(bounds: unknown, options?: object): LeafletMap; remove(): void; invalidateSize(): void };
type LeafletApi = {
  map(container: HTMLElement, options?: object): LeafletMap;
  tileLayer(url: string, options?: object): LeafletLayer;
  marker(position: LeafletPoint, options?: object): LeafletLayer;
  circle(position: LeafletPoint, options?: object): LeafletLayer;
  polyline(points: LeafletPoint[], options?: object): LeafletLayer;
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
      const link = document.createElement("link"); link.rel = "stylesheet"; link.href = leafletCss; link.dataset.supplyosLeaflet = "true"; document.head.appendChild(link);
    }
    if (!script) {
      script = document.createElement("script"); script.src = leafletScript; script.async = true; script.dataset.supplyosLeaflet = "true"; document.head.appendChild(script);
    }
    script.addEventListener("load", () => window.L ? resolve(window.L) : reject(new Error("The map library loaded without its API.")), { once: true });
    script.addEventListener("error", () => reject(new Error("Could not load the map library. Check your internet connection or content blocker.")), { once: true });
    if (window.L) resolve(window.L);
  });
}

function distanceLabel(value: number | null | undefined) {
  if (value == null || !Number.isFinite(value)) return "Distance unavailable";
  if (value < 1000) return `${Math.round(value)} m to factory`;
  return `${(value / 1000).toFixed(1)} km to factory`;
}

export function RouteMap({ routes, trucks = routes.flatMap(route => route.truck ? [route.truck] : []), factory, employees = [] }: { routes: RouteLoad[]; trucks?: RouteTruck[]; factory?: RouteFactory | null; employees?: EmployeeLocation[] }) {
  const elementRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<LeafletMap | null>(null);
  const layersRef = useRef<LeafletLayerGroup | null>(null);
  const hasFittedRef = useRef(false);
  const [mapError, setMapError] = useState("");
  const [mapReady, setMapReady] = useState(false);
  const [reloadKey, setReloadKey] = useState(0);
  const geocodedStopCount = routes.reduce((sum, route) => sum + route.stops.filter(stop => stop.latitude !== null && stop.longitude !== null).length, 0);
  const positionedTruckCount = trucks.filter(truck => truck.latitude !== null && truck.longitude !== null).length;
  const hasFactoryPoint = factory?.latitude != null && factory.longitude != null;

  useEffect(() => {
    let cancelled = false;
    let map: LeafletMap | null = null;
    loadLeaflet().then(L => {
      if (cancelled || !elementRef.current) return;
      hasFittedRef.current = false;
      map = L.map(elementRef.current, { scrollWheelZoom: true, zoomControl: true }).setView([30.3753, 69.3451], 5);
      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", { maxZoom: 19, attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors' }).addTo(map);
      mapRef.current = map;
      layersRef.current = L.layerGroup().addTo(map);
      hasFittedRef.current = false;
      window.setTimeout(() => map?.invalidateSize(), 100);
      setMapError("");
      setMapReady(true);
    }).catch(error => { if (!cancelled) setMapError(error instanceof Error ? error.message : "Map could not be loaded."); });
    return () => {
      cancelled = true;
      map?.remove();
      mapRef.current = null;
      layersRef.current = null;
      setMapReady(false);
    };
  }, [reloadKey]);

  // Redraw only the marker/route layer as GPS pings arrive. The base map and zoom remain stable.
  useEffect(() => {
    const L = window.L;
    const map = mapRef.current;
    const layer = layersRef.current;
    if (!mapReady || !L || !map || !layer) return;
    layer.clearLayers();
    const points: LeafletPoint[] = [];
    const factoryPoint: LeafletPoint | null = factory && hasFactoryPoint
      ? [Number(factory.latitude), Number(factory.longitude)]
      : null;

    if (factoryPoint && factory) {
      points.push(factoryPoint);
      L.circle(factoryPoint, { radius: factory.radiusM || 250, color: "#15936d", fillColor: "#32b98d", fillOpacity: 0.12, weight: 2 }).addTo(layer);
      L.marker(factoryPoint).addTo(layer).bindPopup(`<strong>Factory / fleet base</strong><br>${escapeHtml(factory.name)}<br>${escapeHtml(factory.address || "Address not set")}<br>Shared geofence: ${factory.radiusM} m`);
    }

    const uniqueTrucks = [...new Map(trucks.map(truck => [truck.id, truck])).values()];
    uniqueTrucks.forEach(truck => {
      if (truck.latitude === null || truck.longitude === null) return;
      const point: LeafletPoint = [Number(truck.latitude), Number(truck.longitude)];
      points.push(point);
      const currentLoad = routes
        .filter(route => route.truck?.id === truck.id && ["in_transit", "ready", "planned"].includes(route.status))
        .sort((a, b) => ["in_transit", "ready", "planned"].indexOf(a.status) - ["in_transit", "ready", "planned"].indexOf(b.status))[0];
      const state = truck.factoryGeofenceState || "unknown";
      const locationFresh = !!truck.locationUpdatedAt && Date.now() - new Date(truck.locationUpdatedAt).getTime() <= 120000 && ["phone_gps", "hardware_gps"].includes(truck.locationSource ?? "");
      const isDemoPosition = (truck.currentCity ?? "").startsWith("DEMO ") || (truck.currentCity ?? "").startsWith("Factory / dispatch yard");
      const freshnessLabel = locationFresh ? "LIVE GPS" : isDemoPosition ? "SIMULATED DEMO POSITION — NOT LIVE GPS" : truck.locationUpdatedAt ? "STALE / UNVERIFIED" : "NO REPORT";
      L.marker(point).addTo(layer).bindPopup(`<strong>${escapeHtml(truck.registrationNo)}</strong><br>${escapeHtml(truck.name)}<br>Driver: ${escapeHtml(truck.driverName || "Not set")}<br>Fleet status: ${escapeHtml(truck.status.replaceAll("_", " "))}<br>${currentLoad ? `Current load: ${escapeHtml(currentLoad.loadNo)}<br>` : "No open load assigned<br>"}Straight-line to factory: ${escapeHtml(distanceLabel(truck.factoryDistanceM))}<br>Factory geofence: ${escapeHtml(state.replaceAll("_", " "))}<br>Location source: ${escapeHtml(truck.locationSource ?? "unknown")}<br>GPS accuracy: ${truck.locationAccuracyM == null ? "not reported" : `${Math.round(truck.locationAccuracyM)} m`}<br>Tracking freshness: ${freshnessLabel}<br>Last received: ${escapeHtml(truck.locationUpdatedAt ? new Date(truck.locationUpdatedAt).toLocaleString() : "No report")}`);
    });

    employees.forEach(employee => {
      if (employee.latitude === null || employee.longitude === null) return;
      const point: LeafletPoint = [employee.latitude, employee.longitude];
      points.push(point);
      const fresh = !!employee.locationUpdatedAt && Date.now() - new Date(employee.locationUpdatedAt).getTime() <= 120000;
      const freshness = fresh ? "LIVE" : employee.locationUpdatedAt ? "STALE — last known position" : "WAITING FOR FIRST GPS FIX";
      const circleColor = !fresh ? "#d97706" : employee.geofenceState === "inside" ? "#15803d" : employee.geofenceState === "nearby" ? "#ca8a04" : employee.geofenceState === "outside" ? "#dc2626" : "#64748b";
      L.circle(point, { radius: Math.max(18, Math.min(employee.accuracyM ?? 35, 150)), color: circleColor, fillColor: circleColor, fillOpacity: 0.65, weight: 2 }).addTo(layer);
      L.marker(point).addTo(layer).bindPopup(`<strong>Employee: ${escapeHtml(employee.employeeName)}</strong><br>Shift: active<br>Location: ${freshness}<br>Factory geofence: ${escapeHtml(employee.geofenceState.replaceAll("_", " "))}<br>Distance from factory: ${employee.distanceM == null ? "unknown" : `${Math.round(employee.distanceM)} m`}<br>GPS accuracy: ${employee.accuracyM == null ? "not reported" : `${Math.round(employee.accuracyM)} m`}<br>Last received: ${escapeHtml(employee.locationUpdatedAt ? new Date(employee.locationUpdatedAt).toLocaleString() : "No report")}<br>Shift started: ${escapeHtml(new Date(employee.startedAt).toLocaleString())}`);
    });

    routes.forEach(route => {
      const stopEntries = route.stops.filter(stop => stop.latitude !== null && stop.longitude !== null);
      const stopPoints = stopEntries.map(stop => [Number(stop.latitude), Number(stop.longitude)] as LeafletPoint);
      stopEntries.forEach((stop, index) => {
        const point = stopPoints[index]; points.push(point);
        L.marker(point).addTo(layer).bindPopup(`<strong>Stop ${index + 1}: ${escapeHtml(stop.bookingNo)}</strong><br>${escapeHtml(stop.customerName)}<br>${escapeHtml(stop.address)}<br>${escapeHtml([stop.city, stop.province].filter(Boolean).join(", "))}<br>Geofence: ${escapeHtml((stop.geofenceState || "not checked").replaceAll("_", " "))}${stop.distanceM != null ? `<br>Distance: ${Math.round(stop.distanceM)} m` : ""}`);
        L.circle(point, { radius: route.radiusM || 250, color: "#de7d36", fillColor: "#f0ad67", fillOpacity: 0.12, weight: 1 }).addTo(layer);
      });
      const routeTruck = route.truck;
      const truckPoint = routeTruck && routeTruck.latitude !== null && routeTruck.longitude !== null ? [Number(routeTruck.latitude), Number(routeTruck.longitude)] as LeafletPoint : null;
      // Every dispatch route starts at the shared factory. For a moving load the truck marker
      // sits between the factory and its destination stops, so the map explains the trip origin.
      const connectorPoints = route.status === "in_transit"
        ? [...(factoryPoint ? [factoryPoint] : []), ...(truckPoint ? [truckPoint] : []), ...stopPoints]
        : [...(factoryPoint ? [factoryPoint] : []), ...stopPoints];
      const gpsIsFresh = !!routeTruck?.locationUpdatedAt
        && Date.now() - new Date(routeTruck.locationUpdatedAt).getTime() <= 120000
        && ["phone_gps", "hardware_gps"].includes(routeTruck.locationSource ?? "");
      const lineIsVerifiedLive = route.status === "in_transit" && gpsIsFresh;
      if (connectorPoints.length > 1) L.polyline(connectorPoints, {
        color: lineIsVerifiedLive ? "#3977e7" : route.status === "in_transit" ? "#d97706" : "#8b9cb5",
        weight: 3, opacity: lineIsVerifiedLive ? 0.9 : 0.65,
        dashArray: lineIsVerifiedLive ? undefined : "6 7",
      }).addTo(layer);
    });

    if (!hasFittedRef.current && points.length > 1) { map.fitBounds(L.latLngBounds(points), { padding: [28, 28], maxZoom: 12 }); hasFittedRef.current = true; }
    else if (!hasFittedRef.current && points.length === 1) { map.setView(points[0], 11); hasFittedRef.current = true; }
    window.setTimeout(() => map.invalidateSize(), 80);
  }, [routes, trucks, factory, employees, hasFactoryPoint, mapReady, reloadKey]);

  return <section className="panel route-map-panel">
    <div className="panel-heading"><div><h2>Live fleet map</h2><p>Routes run from the configured factory to shop stops. Solid blue means fresh live GPS; dashed orange means in-transit but unverified/demo position. Lines are straight planning connectors, not road navigation.</p></div><button type="button" className="button button-secondary button-small" onClick={() => { setMapReady(false); setMapError(""); setReloadKey(value => value + 1); }}><RotateCw size={14}/> Reload map</button></div>
    <div className="route-map-summary"><span><Navigation size={14}/>{positionedTruckCount} trucks with location</span><span><MapPinned size={14}/>{geocodedStopCount} mapped customer stops</span><span>{employees.length} active employee shifts</span><span>{hasFactoryPoint ? "Factory base configured" : "Factory base not configured"}</span></div>
    <div className="route-map-container" ref={elementRef} aria-label="Live interactive fleet and factory geofence map" />
    {mapError && <div className="route-map-error"><AlertTriangle size={16}/><span>{mapError}</span></div>}
    {!mapError && !mapReady && <div className="route-map-loading"><span className="dispatch-spinner"/> Loading fleet map…</div>}
    {positionedTruckCount === 0 && employees.every(employee => employee.latitude === null || employee.longitude === null) && <div className="route-map-hint">No truck or employee has reported coordinates yet. Start a live GPS session from the company phone to place it on this map.</div>}
    {!hasFactoryPoint && <div className="route-map-hint">Set the factory gate coordinates below once. Every truck will then show its distance from this same base and inside/nearby/outside state.</div>}
    <div className="route-map-legend"><span><i className="route-legend-dot" style={{ background: "#15936d" }}/>Factory geofence</span><span><i className="route-legend-dot" style={{ background: "#3977e7" }}/>Fresh live GPS route</span><span><i className="route-legend-dot" style={{ background: "#d97706" }}/>Demo / unverified route</span><span><i className="route-legend-dot" style={{ background: "#de7d36" }}/>Customer stop radius</span><span><i className="route-legend-dot" style={{ background: "#15803d" }}/>Employee live GPS (orange = stale)</span></div>
  </section>;
}

function escapeHtml(value: string) { return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#039;"); }
