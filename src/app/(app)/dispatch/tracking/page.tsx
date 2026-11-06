import type { Metadata } from "next";
import { requireUser } from "@/lib/server-auth";
import { saveDriverAssignment, deactivateDriverAssignment } from "../tracking-actions";

export const metadata: Metadata = { title: "Driver tracking setup" };

type Membership = { user_id: string; role: string };
type Truck = { id: string; registration_no: string; display_name: string; status: string };
type Assignment = { id: string; truck_id: string; driver_user_id: string; active: boolean; created_at: string; dispatch_trucks: { registration_no: string; display_name: string } | { registration_no: string; display_name: string }[] | null };
const one = <T,>(value: T | T[] | null | undefined): T | null => Array.isArray(value) ? value[0] ?? null : value ?? null;

export default async function DriverTrackingSetupPage({ searchParams }: { searchParams: Promise<{ success?: string; error?: string }> }) {
  const params = await searchParams;
  const { supabase, user } = await requireUser();
  const { data: current } = await supabase.from("memberships").select("organization_id,role").eq("user_id", user.id).maybeSingle();
  if (!current) return <div className="page-stack"><h1>Driver tracking setup</h1><div className="notice notice-error">Your account is not linked to a factory workspace.</div></div>;
  if (!["owner", "admin", "manager", "dispatcher"].includes(current.role)) return <div className="page-stack"><h1>Driver tracking setup</h1><div className="notice notice-error">Only owners, admins, managers, or dispatchers can manage driver-to-truck assignments.</div></div>;
  const [membershipResult, truckResult, assignmentResult] = await Promise.all([
    supabase.from("memberships").select("user_id,role").eq("organization_id", current.organization_id).order("created_at"),
    supabase.from("dispatch_trucks").select("id,registration_no,display_name,status").eq("organization_id", current.organization_id).order("registration_no"),
    supabase.from("dispatch_truck_driver_assignments").select("id,truck_id,driver_user_id,active,created_at,dispatch_trucks(registration_no,display_name)").eq("organization_id", current.organization_id).order("created_at", { ascending: false }),
  ]);
  const members = (membershipResult.data ?? []) as unknown as Membership[];
  const trucks = (truckResult.data ?? []) as Truck[];
  const assignments = (assignmentResult.data ?? []) as unknown as Assignment[];
  const userIds = [...new Set([...members.map(item => item.user_id), ...assignments.map(item => item.driver_user_id)])];
  const { data: profileRows, error: profileError } = userIds.length ? await supabase.from("profiles").select("id,full_name").in("id", userIds) : { data: [], error: null };
  const profileNames = new Map((profileRows ?? []).map(profile => [profile.id, profile.full_name]));
  const activeAssignments = assignments.filter(item => item.active);
  const driverMembers = members.filter(member => member.role === "staff");
  const dataError = membershipResult.error ?? truckResult.error ?? assignmentResult.error ?? profileError;
  return <div className="page-stack">
    <div className="page-heading-row"><div><div className="eyebrow">OPERATIONS / FLEET VISIBILITY</div><h1>Driver tracking setup</h1><p>Pair a SupplyOS workspace user with a truck. The driver app will only offer that driver’s assigned loads when they are in transit and the truck pass is cleared.</p></div><a className="button button-secondary" href="/routes">Open live fleet map</a></div>
    {params.success ? <div className="notice notice-success">{params.success}</div> : null}
    {params.error ? <div className="notice notice-error">{params.error}</div> : null}
    {dataError ? <div className="notice notice-error">Could not load assignments: {dataError.message}. Confirm the tracking migration is applied.</div> : null}
    <section className="panel"><div className="panel-heading"><div><h2>Assign a driver to a truck</h2><p>Drivers must have an account and be staff members of this workspace first.</p></div></div>
      <form action={async (formData) => { "use server"; await saveDriverAssignment(formData); }} className="route-factory-form">
        <label>Truck<select name="truck_id" required defaultValue=""><option value="" disabled>Select truck</option>{trucks.map(truck => <option key={truck.id} value={truck.id}>{truck.registration_no} · {truck.display_name} ({truck.status})</option>)}</select></label>
        <label>Driver / workspace member<select name="driver_user_id" required defaultValue=""><option value="" disabled>Select driver account</option>{driverMembers.map(member => <option key={member.user_id} value={member.user_id}>{profileNames.get(member.user_id) || "Unnamed user"} · {member.role} · {member.user_id.slice(0, 8)}</option>)}</select></label>
        <button className="button button-primary" type="submit">Save driver assignment</button>
      </form>
      <p className="muted">Driver accounts are selected from existing workspace memberships. Share the driver app only with approved drivers; do not create shared driver logins.</p>
    </section>
    <section className="panel"><div className="panel-heading"><div><h2>Current assignments</h2><p>{activeAssignments.length} active truck-driver pairing(s). A truck can have one active primary driver.</p></div><span className="table-count">{assignments.length} records</span></div>
      <div className="table-scroll"><table className="data-table"><thead><tr><th>Truck</th><th>Driver</th><th>Status</th><th>Assigned</th><th>Action</th></tr></thead><tbody>{assignments.map(item => <tr key={item.id}><td><strong>{one(item.dispatch_trucks)?.registration_no ?? item.truck_id}</strong><div className="muted">{one(item.dispatch_trucks)?.display_name ?? "Truck"}</div></td><td>{profileNames.get(item.driver_user_id) || "Unnamed user"}<div className="muted">{item.driver_user_id.slice(0, 8)}…</div></td><td><span className={`dispatch-status ${item.active ? "dispatch-status-delivered" : "dispatch-status-cancelled"}`}>{item.active ? "Active" : "Inactive"}</span></td><td>{new Date(item.created_at).toLocaleDateString()}</td><td>{item.active ? <form action={async (formData) => { "use server"; await deactivateDriverAssignment(formData); }}><input type="hidden" name="assignment_id" value={item.id}/><button className="button button-secondary button-small" type="submit">Deactivate</button></form> : "—"}</td></tr>)}{!assignments.length ? <tr><td colSpan={5}>No driver assignments yet.</td></tr> : null}</tbody></table></div>
    </section>
  </div>;
}
