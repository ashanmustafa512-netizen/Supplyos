import { AppShell } from "@/components/app-shell";
import { getWorkspace, requireUser } from "@/lib/server-auth";

export default async function PrivateLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const { supabase, user } = await requireUser();
  const { organization, membership } = await getWorkspace(supabase, user.id);
  return <AppShell email={user.email ?? "Signed-in user"} workspaceName={organization?.name ?? "Factory workspace"} role={membership?.role ?? "Unassigned"}>{children}</AppShell>;
}
