import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { getWorkspace, requireUser } from "@/lib/server-auth";
import { canManageTeamLocations } from "@/lib/access";
import { TeamAccessManager } from "@/components/team-access-manager";

export const metadata: Metadata = { title: "Team accounts" };

export default async function TeamAccessPage() {
  const { supabase, user } = await requireUser();
  const { membership } = await getWorkspace(supabase, user.id);
  if (!membership || !canManageTeamLocations(membership.role)) redirect("/dashboard");

  return (
    <div className="page-stack">
      <div className="page-heading-row">
        <div>
          <div className="eyebrow">OWNER / ACCESS CONTROL</div>
          <h1>Team accounts</h1>
          <p>Create separate manager and employee logins for this factory. Each person signs in with their own email and password.</p>
        </div>
      </div>
      <TeamAccessManager/>
    </div>
  );
}
