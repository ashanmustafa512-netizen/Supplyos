/** Normalize role values read from Supabase or legacy rows before authorization checks. */
export function normalizeRole(role: unknown): string {
  return String(role ?? "").trim().toLowerCase().replace(/[\s-]+/g, "_");
}

const accountingRoles = new Set(["owner", "admin", "manager", "accountant"]);
const payrollRoles = new Set(["owner", "admin", "manager", "accountant"]);
const salesRecoveryRoles = new Set(["owner", "admin", "manager", "accountant", "staff"]);
const fleetTrackingRoles = new Set(["owner", "admin", "manager", "dispatcher"]);

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
