"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { Activity, MapPin, RefreshCw, ShieldCheck, Signal, SignalZero } from "lucide-react";
import { RouteMap, type EmployeeLocation, type RouteFactory } from "@/components/route-map";
import { createClient } from "@/lib/supabase/client";

type SessionRow = {
  id: string;
  user_id: string;
  employee_name: string;
  current_latitude: number | null;
  current_longitude: number | null;
  last_location_at: string | null;
  current_location_accuracy_m: number | null;
  factory_distance_m: number | null;
  factory_geofence_state: string;
  started_at: string;
};

const STALE_AFTER_MS = 120_000;

function mapRow(row: SessionRow): EmployeeLocation {
  return {
    id: row.id,
    userId: row.user_id,
    employeeName: row.employee_name,
    latitude: row.current_latitude == null ? null : Number(row.current_latitude),
    longitude: row.current_longitude == null ? null : Number(row.current_longitude),
    locationUpdatedAt: row.last_location_at,
    accuracyM: row.current_location_accuracy_m == null ? null : Number(row.current_location_accuracy_m),
    distanceM: row.factory_distance_m == null ? null : Number(row.factory_distance_m),
    geofenceState: row.factory_geofence_state || "unknown",
    startedAt: row.started_at,
  };
}

function isFresh(value: string | null) {
  if (!value) return false;
  const timestamp = new Date(value).getTime();
  return Number.isFinite(timestamp) && Date.now() - timestamp <= STALE_AFTER_MS;
}

function timeLabel(value: string | null) {
  if (!value) return "No GPS update yet";
  const timestamp = new Date(value);
  if (!Number.isFinite(timestamp.getTime())) return "Timestamp unavailable";
  return timestamp.toLocaleString();
}

export function TeamLocationMap({
  organizationId,
  initialEmployees,
  factory,
}: {
  organizationId: string;
  initialEmployees: EmployeeLocation[];
  factory: RouteFactory | null;
}) {
  const [employees, setEmployees] = useState(initialEmployees);
  const [refreshing, setRefreshing] = useState(false);
  const [lastRefreshAt, setLastRefreshAt] = useState(() => new Date().toISOString());
  const [notice, setNotice] = useState("");

  const refresh = useCallback(async () => {
    const supabase = createClient();
    setRefreshing(true);
    const { data, error } = await supabase
      .from("employee_location_sessions")
      .select("id,user_id,employee_name,current_latitude,current_longitude,last_location_at,current_location_accuracy_m,factory_distance_m,factory_geofence_state,started_at")
      .eq("organization_id", organizationId)
      .is("ended_at", null)
      .order("started_at", { ascending: false })
      .limit(500);

    if (error) {
      setNotice("Could not refresh team locations. Showing the last successfully loaded positions.");
    } else {
      setEmployees(((data ?? []) as SessionRow[]).map(mapRow));
      setNotice("");
      setLastRefreshAt(new Date().toISOString());
    }
    setRefreshing(false);
  }, [organizationId]);

  useEffect(() => {
    let active = true;
    const supabase = createClient();
    const channel = supabase
      .channel(`owner-team-location-${organizationId}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "employee_location_sessions",
          filter: `organization_id=eq.${organizationId}`,
        },
        () => {
          if (active) void refresh();
        },
      )
      .subscribe();

    const poll = window.setInterval(() => {
      if (active && document.visibilityState === "visible") void refresh();
    }, 30_000);

    const onVisible = () => {
      if (document.visibilityState === "visible") void refresh();
    };
    document.addEventListener("visibilitychange", onVisible);

    return () => {
      active = false;
      window.clearInterval(poll);
      document.removeEventListener("visibilitychange", onVisible);
      void supabase.removeChannel(channel);
    };
  }, [organizationId, refresh]);

  const freshEmployees = useMemo(
    () => employees.map(person => isFresh(person.locationUpdatedAt)
      ? person
      : { ...person, latitude: null, longitude: null }),
    [employees],
  );
  const freshCount = employees.filter(person => isFresh(person.locationUpdatedAt) && person.latitude != null && person.longitude != null).length;
  const staleCount = employees.length - freshCount;

  return (
    <div className="page-stack">
      <div className="metric-grid metric-grid-three">
        <div className="metric-card">
          <div className="metric-card-top"><span className="metric-icon metric-blue"><Activity size={17}/></span><span className="metric-trend">Current shifts</span></div>
          <div className="metric-value">{employees.length}</div>
          <div className="metric-label">Managers and employees sharing during a shift</div>
        </div>
        <div className="metric-card">
          <div className="metric-card-top"><span className="metric-icon metric-green"><Signal size={17}/></span><span className="metric-trend">Fresh GPS</span></div>
          <div className="metric-value">{freshCount}</div>
          <div className="metric-label">Positions updated in the last 2 minutes</div>
        </div>
        <div className="metric-card">
          <div className="metric-card-top"><span className="metric-icon metric-amber"><SignalZero size={17}/></span><span className="metric-trend">Needs attention</span></div>
          <div className="metric-value">{staleCount}</div>
          <div className="metric-label">Stale or not-yet-reported positions</div>
        </div>
      </div>

      {notice && <div className="notice notice-error">{notice}</div>}

      <section className="panel">
        <div className="panel-heading">
          <div>
            <h2>Live team map</h2>
            <p>Only active, consented manager and employee work-shift sessions appear here. Stale coordinates are not shown as live markers.</p>
          </div>
          <button className="button button-secondary button-small" type="button" onClick={() => void refresh()} disabled={refreshing}>
            <RefreshCw size={14} className={refreshing ? "spin-icon" : ""}/> {refreshing ? "Refreshing…" : "Refresh"}
          </button>
        </div>
        <RouteMap routes={[]} trucks={[]} factory={factory} employees={freshEmployees}/>
        <div className="map-legend"><span><i className="legend-dot legend-green"/> Fresh GPS</span><span><i className="legend-dot legend-amber"/> Stale/unavailable shown in list only</span><span><ShieldCheck size={14}/> Shift consent required</span></div>
      </section>

      <section className="panel">
        <div className="panel-heading">
          <div><h2>Active work shifts</h2><p>GPS timestamps are server accepted update times, not a guarantee of continuous coverage.</p></div>
          <span className="table-count">Last refresh {new Date(lastRefreshAt).toLocaleTimeString()}</span>
        </div>
        <div className="table-scroll">
          <table className="data-table">
            <thead><tr><th>Team member</th><th>Location status</th><th>Last GPS update</th><th>Accuracy</th><th>Factory geofence</th></tr></thead>
            <tbody>
              {employees.map(person => {
                const fresh = isFresh(person.locationUpdatedAt) && person.latitude != null && person.longitude != null;
                return <tr key={person.id}>
                  <td><div className="customer-primary"><span className="customer-avatar">{(person.employeeName[0] || "T").toUpperCase()}</span><span><strong>{person.employeeName}</strong><small>Work shift started {new Date(person.startedAt).toLocaleString()}</small></span></div></td>
                  <td><span className={`status-pill ${fresh ? "status-completed" : "status-pending_approval"}`}><i/>{fresh ? "Live" : "Stale / waiting"}</span></td>
                  <td>{timeLabel(person.locationUpdatedAt)}</td>
                  <td>{person.accuracyM == null ? "—" : `±${Math.round(person.accuracyM)} m`}</td>
                  <td>{person.geofenceState || "unknown"}{person.distanceM == null ? "" : ` · ${Math.round(person.distanceM)} m`}</td>
                </tr>;
              })}
              {!employees.length && <tr><td colSpan={5}>No manager or employee work shifts are currently sharing location.</td></tr>}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
