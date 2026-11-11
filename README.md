# SupplyOS — Factory Distribution & Supply Chain Operations

> **Getting started:** use [`START_HERE.md`](./START_HERE.md) for the simplest local run instructions, environment setup, and troubleshooting. On Windows, double-click [`START_WINDOWS.bat`](./START_WINDOWS.bat).

SupplyOS is a Next.js + TypeScript + Supabase application for a factory/distributor workflow. It includes authentication, a workspace-scoped Postgres database, operational booking and dispatch tools, inventory and purchasing, accounting, sales recovery, payroll, and route/geofence views.

> **Important:** This is a functional MVP, not certified accounting, payroll, transport-permit, or regulatory software. Validate business rules, tax/payroll treatment, supplier/customer records, and local legal requirements before using it for real transactions. All `DEMO` records are fictional.

## Included modules

- **Dashboard:** booking, dispatch, inventory and finance indicators.
- **Bookings:** create and search orders; customer credit and stock checks; approve/reject/cancel/complete; bulk approvals; booking history.
- **Dispatch:** load planning by route, city, province, region, district, tehsil, area, zone, or individual order; capacity-aware route consolidation before loading starts; truck assignment; signed loading checklist; automatically generated pre-departure truck inspection/gate pass; hard dispatch gate until the pass is cleared; bulk dispatch; delivery updates; targets; early warnings; contingencies; CSV reports; printable delivery manifest.
- **Routes & geofencing:** interactive fleet map with all registered trucks, driver/device GPS sharing (browser foreground, roughly 10-second updates), Supabase Realtime updates with a 30-second visibility-aware polling fallback, one shared factory gate geofence per workspace, straight-line distance from each truck to that factory, inside/nearby/outside classification, customer-stop geofences, route incidents, and manual location fallback. Continuous background GPS still requires a dedicated mobile app or telematics device; drawn route connectors are not turn-by-turn/road-optimized navigation.
- **Stock & warehouse:** product catalog, SKU/barcode/category, selling price, unit and production costs, stock balance/reservations, adjustment ledger, suppliers, warehouses, and multi-line purchase orders/receiving. Cost changes are recorded as inventory revaluations; use stock adjustments rather than editing quantity in the product form.
- **Accounting & finance:** account list, date-range reporting, posted ledger revenue/expenses/net result, invoice sales, collections, receivables, supplier liabilities, payroll liabilities, stock valuation, six-month trend, expenses, other income, journal entries, and payment receipts. It distinguishes operational booking value from accounting revenue to avoid double counting.
- **Sales & recovery:** customer invoices from completed demo bookings, partial/full collections, receivable ageing, customer credit exposure, payment receipts, and follow-up tasks for calls, visits, disputes, and payment promises.
- **Payroll:** employee directory and salary components, monthly draft payroll runs, editable overtime/bonus/deductions/tax, approval and payment posting, and draft-only voiding. Payroll is not paid or posted until an authorized user explicitly performs that action.
- **Customers:** customer contacts, regions/cities and delivery geography, credit limit and reliability score.
- **Theme and usability:** browser-persisted light/dark theme, client-side dispatch updates, bulk actions and sharp responsive UI.

## Requirements

- Node.js 20.9+ (Node 22 recommended)
- npm
- Supabase project

## Setup

1. Copy `.env.example` to `.env.local` in the project root and set the Supabase project URL and publishable key. Never put a Supabase service-role key in a browser-facing environment variable or commit `.env.local`.
2. In Supabase Auth → URL Configuration, allow `http://localhost:3000/**` for local testing.
3. Install and start:

   ```bash
   npm install
   npm run dev
   ```

4. Open `http://localhost:3000`, sign in, and use the workspace you created for SupplyOS.

## Fleet tracking and gate control

- Open **Routes & geofencing** and save the actual factory gate latitude/longitude once. The same factory radius and coordinates are used for every truck in the workspace. The factory base is deliberately not guessed or set to a demo coordinate. The connected development workspace currently has no factory coordinates configured; its sample truck GPS points are old (not live), so configure the real gate and connect each truck GPS source before a factory pilot. See `docs/FACTORY_PILOT_CHECKLIST.md`.
- Start **Live GPS sharing** on a GPS-enabled phone/device that travels with the selected truck. Grant browser location permission and keep the page open. The Routes screen receives normal truck changes through Supabase Realtime and performs a 30-second polling fallback; browser GPS fixes are sent approximately every 10 seconds while the browser supplies them. Browser geolocation can pause in the background or when the phone locks; dependable 24/7 tracking needs a supported driver app or truck telematics integration.
- Factory distance is a straight-line (Haversine) estimate, not driving distance or ETA. Map connectors are planning lines rather than turn-by-turn navigation.
- When a load is marked ready, SupplyOS creates a uniquely numbered truck inspection pass. All eight checks must be marked complete to clear it; the database blocks dispatch until the pass is cleared for the truck assigned to that load. Printed pass labels it as an internal factory gate/inspection record, not a government transport permit.
- Smart dispatch first tries existing planned routes that have not begun loading, matching known locality or coordinates and validating order/payload capacity. It can reuse a ready truck only when its GPS report is less than 2 minutes old and it is inside/near the configured factory geofence. Such a load returns to the planning/loading state, its bill manifest can be regenerated, and the loading checklist and inspection pass must be completed again. Loads already in transit are never consolidated.

## Geofencing reliability update

Read [`docs/PRODUCTION_GEOFENCING_GUIDE.md`](./docs/PRODUCTION_GEOFENCING_GUIDE.md) for exact factory coordinate/save behavior, the inside/nearby/outside/unknown states, GPS accuracy and stale-location handling, privacy notes, and publish-readiness checks. The patch migration `20261028190000_workspace_and_geofence_reliability.sql` adds safe recovery for older authenticated accounts with no workspace and makes the factory geofence save RPC validate/echo the persisted coordinates. Apply it only after verifying the baseline and prior geofence migrations.

## Database migrations

For an **existing SupplyOS database that already has the initial and dispatch migrations**, apply the remaining additive migrations in timestamp order. In Supabase SQL Editor, execute each file once, in this order:

1. `20261018063924_finance_stock_payroll_schema.sql`
2. `20261018064909_stock_workflows.sql`
3. `20261018065104_accounting_sales_workflows.sql`
4. `20261018065157_payroll_workflows.sql`
5. `20261018071623_inventory_valuation_safety.sql`
6. `20261018083245_finance_dashboard_reporting.sql`
7. `20261018083658_sales_recovery_tasks.sql`
8. `20261018085917_finance_dashboard_access.sql`
9. `20261018090329_finance_cash_flow_metric.sql`
10. `20261018090835_stock_multi_line_purchase_orders.sql`
11. `20261018091059_sales_recovery_access.sql` (creates/updates the recovery-task access policy and grants)
12. `20261018091410_accounting_manual_journal_manager.sql`
13. `20261018091935_sales_staff_payment_accounts.sql`
14. `20261018092253_stock_workflow_permissions.sql`
15. `20261018092528_accounting_backdated_invoice_due_dates.sql` (allows an overdue invoice due date for historical/backlog invoicing but not before its source booking date)
16. `20261018100022_routes_fleet_truck_pass_smart_consolidation.sql` (shared factory geofence, fleet distance, truck passes, dispatch gate, capacity-aware route consolidation)
17. `20261018101505_consolidation_loading_safety.sql` (restricts consolidation to planned routes where loading has not started and avoids matching unknown/blank destinations)
18. `20261018101749_mark_legacy_in_transit_passes.sql` (labels passes backfilled for already-departed demo loads as historical/unverified)
19. `20261018101926_truck_pass_assignment_edge.sql` (also generates a pass if a truck is assigned after a load has already reached ready status)
20. `20261018102045_truck_pass_indexes.sql` (indexes truck inspection audit-user links)
21. `20261018103435_ready_load_consolidation_reopen.sql` (allows eligible ready trucks at the factory to be reused, resets loading/inspection gates, and refreshes stale bill-pass manifests)
22. `20261018104043_factory_coordinate_constraint_strict.sql` (requires both factory coordinates to be set together, or both left blank)
23. `20261018112451_phone_gps_trip_tracking.sql` (trip-scoped driver GPS sessions)
24. `20261018112601_tracking_safety_and_geofence_hooks.sql` (tracking validation and geofence hooks)
25. `20261018112741_tracking_policy_hardening.sql` (tracking access policy hardening)
26. `20261018112836_tracking_workspace_driver_names.sql` (workspace-scoped driver labels)
27. `20261018112851_tracking_driver_role_enforcement.sql` (driver and manager authorization enforcement)
28. `20261018113019_tracking_assignment_staff_gate.sql` (active driver assignment checks)
29. `20261018113130_tracking_accuracy_aware_geofence.sql` (accuracy-aware GPS classification)
30. `20261018113227_smart_dispatch_requires_trusted_gps.sql` (trusted fresh GPS required for smart dispatch reuse)
31. `20261020190800_employee_shift_location_tracking.sql` (opt-in employee shift sessions)
32. `20261020191000_employee_location_fix_timestamp.sql` (server receipt timestamps and GPS freshness handling)
33. `20261028190000_workspace_and_geofence_reliability.sql` (older-account workspace recovery and verified factory gate persistence)
34. `20261028190500_accuracy_aware_fleet_gps.sql` (separates genuine phone GPS fixes from manual coordinates and gates stop transitions by accuracy)
35. `20261111173000_dashboard_summary_performance.sql` (adds indexed server-side dashboard/booking aggregates and supporting query indexes)

The connected Supabase development project had its earlier dispatch, fleet and finance changes applied before this patch. The two new patch migrations (`20261028190000_workspace_and_geofence_reliability.sql` and `20261028190500_accuracy_aware_fleet_gps.sql`) may still need to be applied. Check the target project's migration history first and apply only these new files if they are not already recorded. **Do not rerun older migrations against an existing project.** The initial schema was bootstrapped separately and may not appear in migration history, so do not run `supabase db push` against that project until its baseline has been reconciled. For a fresh project, apply every migration file in timestamp order, beginning with the initial schema, then the dispatch migrations, then the finance/stock/payroll migrations.

## Performance update

The web shell now memoizes the current authenticated user/workspace within each server render, so the protected layout and page modules do not repeat the same Supabase auth and workspace lookups. Dashboard and Bookings monthly metrics use the `supplyos_dashboard_summary` database function to avoid sending large booking/product lists for aggregation. Apply `20261111173000_dashboard_summary_performance.sql` once after checking the target project's migration history. The Dispatch console memoizes expensive derived collections and inspection-pass lookups. The Routes screen relies on Realtime for normal GPS changes and uses a 30-second, visibility-aware polling fallback.

## Demo data

The connected development workspace has been seeded and checked. For a development workspace only, run `supabase/seed_demo_data.sql` first, then `supabase/seed_finance_demo_data.sql` after all migrations have been applied. The finance seed is designed to be repeatable and labels the records as demo data. It creates sample suppliers, employees, purchase orders, expenses, other income, invoices/partial receipts for demo bookings only, and a draft payroll run. Purchase orders remain unreceived so they do not inflate on-hand stock. **Do not run demo seeds in production or treat fictional values as actual business records.**

## Useful commands

```bash
npm run dev      # local development server
npm run build    # production build
npm run start    # serve production build
npm run lint     # ESLint
```

## Operational caveats

- The Routes page retains manual coordinate entry as a development fallback. For unattended trip-based background tracking, use the native Android app in `mobile-driver/` described in `docs/ANDROID_DRIVER_TRACKING.md`. Every truck’s factory distance is straight-line GPS distance, not driving-distance ETA. Use exact gate/shop coordinates and the dedicated driver app or later telematics feed for unattended fleet tracking.
- The truck inspection pass is an internal pre-departure checklist/gate-control record, not a roadworthiness certificate or government permit. The printed goods bill pass remains a delivery manifest, not a replacement for legally required transport paperwork. The app enforces the eight-check pass before a load can be dispatched.
- Payroll/tax calculations are configurable estimates and need review for local statutory requirements. Draft payroll is not a bank transfer.
- Before production: restrict public sign-up, review every RLS policy and `SECURITY DEFINER` RPC, establish role separation, backup/restore procedures, audit retention, monitoring, automated tests, and accountant review of journal mappings.
- Currency is currently displayed in PKR. Multi-currency conversion, bank reconciliation, and tax filing are not implemented. The Android driver-app source is included, but it still requires real-device, store-policy, security, and deployment testing before production use.

## Structure

- `src/app/(app)/` — module pages and server actions
- `src/components/` — app shell, booking/dispatch consoles, route map, theme controls
- `src/lib/` — Supabase clients, auth and formatting helpers
- `supabase/migrations/` — database schema, policies and transactional workflows
- `supabase/seed_demo_data.sql` — operational demo records
- `supabase/seed_finance_demo_data.sql` — finance, purchasing and payroll demo records

## Android driver phone tracking (new)

The native driver app is in [`mobile-driver/`](mobile-driver/) and the implementation/test guide is [`docs/ANDROID_DRIVER_TRACKING.md`](docs/ANDROID_DRIVER_TRACKING.md). It uses trip-specific consent, Android foreground-service background location, secure session-bound Supabase RPCs, and existing factory/customer geofence calculations. Configure a staff driver account and assign it to a truck in **Dispatch → Driver tracking setup**. Only an in-transit load with a cleared truck inspection pass can be started. The live Routes map receives authorized truck updates via Supabase Realtime and retains a 30-second, visibility-aware polling fallback.

The native Android app has not yet been built or physically tested in this environment because npm dependency installation timed out and no Android SDK/device is attached. Follow the guide's pilot test plan before rolling this out to the full 25-truck fleet.

## Employee location tracking (Android)
The company-phone app supports opt-in work-shift location sharing in addition to trip-based driver tracking. Employees must explicitly start a shift and can stop sharing at any time; location is not collected merely on sign-in or after a shift is ended. Authorized managers can see active employees, last GPS timestamp, accuracy, and factory-geofence state under Routes & geofencing. See `docs/EMPLOYEE_LOCATION_TRACKING.md` for setup and the pilot test plan.
