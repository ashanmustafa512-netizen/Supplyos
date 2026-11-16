/** Normalize role values read from Supabase or legacy rows before authorization checks. */
export function normalizeRole(role: unknown): string {
  return String(role ?? "").trim().toLowerCase().replace(/[\s-]+/g, "_");
}

const ownerRoles = new Set(["owner", "admin"]);
const managerRoles = new Set(["owner", "admin", "manager"]);
const bookingRoles = new Set(["owner", "admin", "manager", "staff"]);
const salesRecoveryRoles = new Set(["owner", "admin", "manager"]);

export function isOwnerRole(role: unknown): boolean {
  return ownerRoles.has(normalizeRole(role));
}

export function canAccessAccounting(role: unknown): boolean {
  return isOwnerRole(role);
}

export function canAccessPayroll(role: unknown): boolean {
  return isOwnerRole(role);
}

export function canAccessSalesRecovery(role: unknown): boolean {
  return salesRecoveryRoles.has(normalizeRole(role));
}

export function canViewTeamLocations(role: unknown): boolean {
  return isOwnerRole(role);
}

export function canCreateBookings(role: unknown): boolean {
  return bookingRoles.has(normalizeRole(role));
}

export function canViewAllBookings(role: unknown): boolean {
  return managerRoles.has(normalizeRole(role));
}

export function canApproveBookings(role: unknown): boolean {
  return isOwnerRole(role);
}

export function canCompleteBookings(role: unknown): boolean {
  return managerRoles.has(normalizeRole(role));
}

export function canCancelBookings(role: unknown): boolean {
  return bookingRoles.has(normalizeRole(role));
}

/** Legacy name retained while the mixed fleet routes screen is retired. */
export function canManageFleetTracking(role: unknown): boolean {
  return canViewTeamLocations(role);
}
