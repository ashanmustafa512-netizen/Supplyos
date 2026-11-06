import { redirect } from "next/navigation";
import { isSupabaseConfigured } from "@/lib/env";
import { createClient } from "@/lib/supabase/server";

export async function requireUser() {
  if (!isSupabaseConfigured) redirect("/setup");
  const supabase = await createClient();
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) redirect("/login");
  return { supabase, user: data.user };
}

export async function getWorkspace(supabase: Awaited<ReturnType<typeof createClient>>, userId: string) {
  let { data: membership, error: membershipError } = await supabase
    .from("memberships")
    .select("organization_id, role")
    .eq("user_id", userId)
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();

  // Older Auth accounts may predate handle_new_user() and therefore have no workspace.
  // The RPC only creates a workspace for auth.uid() and does not accept an arbitrary user ID.
  if (!membership && !membershipError) {
    const { error: bootstrapError } = await supabase.rpc("ensure_my_workspace");
    if (!bootstrapError) {
      const retry = await supabase
        .from("memberships")
        .select("organization_id, role")
        .eq("user_id", userId)
        .order("created_at", { ascending: true })
        .limit(1)
        .maybeSingle();
      membership = retry.data;
      membershipError = retry.error;
    }
  }

  if (membershipError || !membership) return { organization: null, membership: null };
  const { data: organization } = await supabase
    .from("organizations")
    .select("id, name, currency_code")
    .eq("id", membership.organization_id)
    .maybeSingle();
  return { organization, membership };
}
