import { requireWorkspaceRole } from "@/lib/server-auth";

export default async function InventoryLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  await requireWorkspaceRole(["owner", "admin", "manager"]);
  return children;
}
