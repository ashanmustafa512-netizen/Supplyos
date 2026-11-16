import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getWorkspace, requireUser } from "@/lib/server-auth";
import { canManageTeamLocations } from "@/lib/access";
import { TeamLocationMap } from "@/components/team-location-map";
import type { EmployeeLocation, RouteFactory } from "@/components/route-map";

export const metadata: Metadata = { title: "Team live locations" };

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

export default async function TeamPage() {
  const { supabase, user } = await requireUser();
  const { membership, organization } = await getWorkspace(supabase, user.id);
  if (!membership || !canManageTeamLocations(membership.role)) redirect("/dashboard");

  const [sessionsResult, factoryResult] = await Promise.all([
    supabase
      .from("employee_location_sessions")
      .select("id,user_id,employee_name,current_latitude,current_longitude,last_location_at,current_location_accuracy_m,factory_distance_m,factory_geofence_state,started_at")
      .eq("organization_id", membership.organization_id)
      .is("ended_at", null)
      .order("started_at", { ascending: false })
      .limit(500),
    supabase
      .from("organizations")
      .select("name,factory_address,factory_latitude,factory_longitude,factory_geofence_radius_m")
      .eq("id", membership.organization_id)
      .maybeSingle(),
  ]);

  const initialEmployees = ((sessionsResult.data ?? []) as unknown as SessionRow[]).map(mapRow);
  const factoryRow = factoryResult.data;
  const factory: RouteFactory | null = factoryRow ? {
    name: factoryRow.name || organization?.name || "Factory",
    address: factoryRow.factory_address || "",
    latitude: factoryRow.factory_latitude == null ? null : Number(factoryRow.factory_latitude),
    longitude: factoryRow.factory_longitude == null ? null : Number(factoryRow.factory_longitude),
    radiusM: Number(factoryRow.factory_geofence_radius_m ?? 250),
  } : null;

  return (
    <div className="page-stack">
      <div className="page-heading-row">
        <div>
          <div className="eyebrow">OWNER / PEOPLE VISIBILITY</div>
          <h1>Team live locations</h1>
          <p>See active employee and manager work shifts on one map. Location is shared only during an explicitly started shift.</p>
        </div>
      </div>
      {sessionsResult.error && <div className="notice notice-error">Could not load current team shifts: {sessionsResult.error.message}</div>}
      {factoryResult.error && <div className="notice notice-error">Could not load factory geofence details: {factoryResult.error.message}</div>}
      <TeamLocationMap organizationId={membership.organization_id} initialEmployees={initialEmployees} factory={factory}/>
    </div>
  );
}
