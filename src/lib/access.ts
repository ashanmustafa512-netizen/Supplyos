/** Normalize role values read from Supabase or legacy rows before authorization checks. */
export function normalizeRole(role: unknown): string {
  return String(role ?? "").trim().toLowerCase().replace(/[\s-]+/g, "_");
}

const ownerRoles = new Set(["owner", "admin"]);
const managerRoles = new Set(["owner", "admin", "manager"]);
const financeRoles = new Set(["owner", "admin", "accountant"]);
const salesRecoveryRoles = new Set(["owner", "admin", "manager", "accountant"]);

export function isOwnerRole(role: unknown): boolean {
  return ownerRoles.has(normalizeRole(role));
}

export function canAccessAccounting(role: unknown): boolean {
  return financeRoles.has(normalizeRole(role));
}

export function canAccessPayroll(role: unknown): boolean {
  return financeRoles.has(normalizeRole(role));
}

export function canAccessSalesRecovery(role: unknown): boolean {
  return salesRecoveryRoles.has(normalizeRole(role));
}

export function canViewTeamLocations(role: unknown): boolean {
  return managerRoles.has(normalizeRole(role));
}

/** Legacy name retained for older call sites while fleet navigation is retired. */
export function canManageFleetTracking(role: unknown): boolean {
  return canViewTeamLocations(role);
}
