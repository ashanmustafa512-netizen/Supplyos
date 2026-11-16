import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getWorkspace, requireUser } from "@/lib/server-auth";
import { canViewTeamLocations } from "@/lib/access";
import { TeamLocationMap, type TeamLocation } from "@/components/team-location-map";

export const metadata: Metadata = { title: "Team live location" };

export default async function TeamLocationPage() {
  const { supabase, user } = await requireUser();
  const { organization, membership } = await getWorkspace(supabase, user.id);
  if (!organization || !membership || !canViewTeamLocations(membership.role)) {
    redirect("/dashboard");
  }

  const [sessionsResult, factoryResult] = await Promise.all([
    supabase.from("employee_location_sessions")
      .select("id,user_id,employee_name,current_latitude,current_longitude,last_location_at,current_location_accuracy_m,factory_distance_m,factory_geofence_state,started_at")
      .eq("organization_id", organization.id)
      .is("ended_at", null)
      .order("last_location_at", { ascending: false })
      .limit(500),
    supabase.from("organizations")
      .select("name,factory_latitude,factory_longitude,factory_geofence_radius_m")
      .eq("id", organization.id)
      .maybeSingle(),
  ]);

  const rawSessions = (sessionsResult.data ?? []) as unknown as Array<Record<string, unknown>>;
  const userIds = [...new Set(rawSessions.map(row => String(row.user_id)))];
  const { data: memberships } = userIds.length
    ? await supabase.from("memberships").select("user_id,role").eq("organization_id", organization.id).in("user_id", userIds)
    : { data: [] as Array<{user_id:string;role:string}> };
  const roleByUser = new Map((memberships ?? []).map(item => [item.user_id, item.role]));

  const locations: TeamLocation[] = rawSessions.map(row => ({
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
  }));

  const factory = factoryResult.data ? {
    name: String(factoryResult.data.name ?? organization.name),
    latitude: factoryResult.data.factory_latitude == null ? null : Number(factoryResult.data.factory_latitude),
    longitude: factoryResult.data.factory_longitude == null ? null : Number(factoryResult.data.factory_longitude),
    radiusM: Number(factoryResult.data.factory_geofence_radius_m ?? 250),
  } : null;

  return (
    <div className="page-stack">
      <div className="page-heading-row">
        <div><div className="eyebrow">OWNER / TEAM OVERSIGHT</div><h1>Team live location</h1><p>See active employee and manager shifts, last GPS updates, and factory geofence status.</p></div>
      </div>
      {sessionsResult.error && <div className="notice notice-error">Team location data could not be loaded: {sessionsResult.error.message}</div>}
      <TeamLocationMap organizationId={organization.id} initialLocations={locations} factory={factory}/>
      <p className="helper-line">Location is collected only during an explicitly started work shift. A stale marker is the last received position, not a live position.</p>
    </div>
  );
}
