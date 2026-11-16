# SupplyOS Role-Based Apps

SupplyOS uses one Supabase project and one shared business database with three role-specific applications.

## Roles

- **Owner / Admin:** overview, booking approvals, team live location, stock, accounting, payroll, and sales & recovery.
- **Manager:** operations overview, bookings, stock & warehouse, sales & recovery, plus work-shift location sharing.
- **Staff / Employee:** new booking, own booking history, and native work-shift location sharing.

The database is the final permission boundary. Hiding a navigation item does not grant or deny access by itself.

## Mobile applications

| App folder | Android application ID | Role |
| --- | --- | --- |
| `mobile-admin` | `com.supplyos.owner` | Owner |
| `mobile-manager` | `com.supplyos.manager` | Manager |
| `mobile-driver` | `com.supplyos.employee` | Employee |

The Owner and Manager apps are separate WebView shells of the same responsive web app. The signed-in Supabase membership controls which app experience and routes are available.

The Employee app is a native Expo app. It includes shop booking creation, the employee's own booking list, and native background work-shift location updates.

## Environment

Create local, untracked environment files:

**`mobile-admin/.env`**
```dotenv
EXPO_PUBLIC_OWNER_URL=https://YOUR_SUPPLYOS_DOMAIN
```

**`mobile-manager/.env`**
```dotenv
EXPO_PUBLIC_MANAGER_URL=https://YOUR_SUPPLYOS_DOMAIN
```

**`mobile-driver/.env`**
```dotenv
EXPO_PUBLIC_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_your_key_here
```

Use the Supabase publishable key only. Never place a Supabase service-role or secret key in an Expo app or any `EXPO_PUBLIC_*` variable.

## Local commands

Install dependencies in each Expo app, then start it:

```bash
cd mobile-admin
npm install
npx expo start
```

Repeat in `mobile-manager` and `mobile-driver`.

From the repository root, run the type checks:

```bash
npm run check:mobile
```

The root web checks run with:

```bash
npm run check
```

## Location behavior

- An employee explicitly agrees to shift tracking, grants foreground and background location permission, and starts a work shift.
- The Employee app's native Expo location task continues during the active shift where Android permissions and device power settings allow it.
- A manager starts a work shift from the Manager app's location panel. The mobile WebView uses browser geolocation while the Manager app is active. Browser geolocation can pause when the app is backgrounded; the owner map marks old updates as stale.
- The Owner app displays both manager and employee sessions, server-calculated geofence states, GPS accuracy, last update time, and stale status.
- The owner can close an active session from the live team map. The employee/manager can also end their own shift.
- Location sessions are not intended to track staff outside their declared working shift.

## Retired modules

Dispatch, truck routes/tracking setup, and the standalone Customers tab are removed from active navigation. Existing dispatch data and historical records are retained. Shop records remain available through the booking catalogue, with a small Add Shop workflow inside booking creation for owners/managers.

## Database migrations

The role-based application migrations are under `supabase/migrations/` with timestamp prefix `20261116`. Review and apply them in order with the project's normal Supabase migration process before deploying the new application code. They change RLS policies and replace existing SECURITY DEFINER RPCs while preserving their transactional inventory, credit, accounting, payroll, and sales logic.
