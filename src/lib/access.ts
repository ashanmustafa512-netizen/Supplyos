/** Normalize role values read from Supabase or legacy rows before authorization checks. */
export function normalizeRole(role: unknown): string {
  return String(role ?? "").trim().toLowerCase().replace(/[\s-]+/g, "_");
}

const ownerRoles = new Set(["owner", "admin"]);
const accountingRoles = new Set(["owner", "admin", "accountant"]);
const payrollRoles = new Set(["owner", "admin"]);
const salesRecoveryRoles = new Set(["owner", "admin", "manager", "accountant"]);
const fleetTrackingRoles = new Set(["owner", "admin"]);
const inventoryRoles = new Set(["owner", "admin", "manager"]);
const bookingCreationRoles = new Set(["owner", "admin", "manager", "staff"]);

export function isOwnerOrAdmin(role: unknown): boolean {
  return ownerRoles.has(normalizeRole(role));
}

export function canApproveBookings(role: unknown): boolean {
  return isOwnerOrAdmin(role);
}

export function canCompleteBookings(role: unknown): boolean {
  return ["owner", "admin", "manager"].includes(normalizeRole(role));
}

export function canCreateBookings(role: unknown): boolean {
  return bookingCreationRoles.has(normalizeRole(role));
}

export function canManageInventory(role: unknown): boolean {
  return inventoryRoles.has(normalizeRole(role));
}

export function canAccessAccounting(role: unknown): boolean {
  return accountingRoles.has(normalizeRole(role));
}

export function canAccessPayroll(role: unknown): boolean {
  return payrollRoles.has(normalizeRole(role));
}

export function canAccessSalesRecovery(role: unknown): boolean {
  return salesRecoveryRoles.has(normalizeRole(role));
}

export function canManageFleetTracking(role: unknown): boolean {
  return fleetTrackingRoles.has(normalizeRole(role));
}

export function canManageTeamLocations(role: unknown): boolean {
  return isOwnerOrAdmin(role);
}
