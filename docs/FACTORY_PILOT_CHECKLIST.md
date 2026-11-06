# SupplyOS factory pilot readiness checklist

Use this checklist before showing live operations to a factory or putting real loads through the system.

## 1. Factory base and geofence

- In **Routes & geofencing**, enter the actual dispatch gate address and verified latitude/longitude from a phone GPS reading or a trusted map source.
- Choose a radius appropriate for the site (the default is 250 m); verify the circle visually on the map and test a known point inside and outside it.
- Do not use a customer location, approximate town centre, or sample/demo coordinates as the factory base.
- The connected development workspace currently has no factory coordinates configured. Until the real gate point is saved, factory-distance and inside/nearby/outside classifications are not production-ready.

## 2. Live truck location

- Pair each truck with a driver phone or supported GPS/telematics device and select the correct truck in **Live GPS sharing**.
- Grant browser location permission and keep the page open for the browser-based MVP tracker. Test that the timestamp refreshes and that the truck marker moves.
- The current development dataset contains old sample GPS points (not live positions). Do not present those as real-time fleet tracking.
- A browser page can pause in the background or when a phone locks. For unattended 24/7 tracking, integrate a dedicated driver app or vehicle telematics provider before the pilot.
- Distances shown to the factory are straight-line estimates, not road mileage or an ETA.

## 3. Dispatch and load consolidation

- Verify each truck's legal payload, order capacity, driver, registration and maintenance status.
- Confirm customer coordinates/address data are accurate enough to match similar or nearby routes.
- Smart planning may add an order to a compatible planned load only if loading has not started and capacity allows. A ready load can be reused only when its GPS is fresh (within two minutes), it is near/inside the configured factory geofence, and the route/capacity checks pass. This reopens the load and resets loading and truck inspection checks.
- Loads already in transit are never consolidated. Do not treat straight-line proximity as proof of a drivable route.
- Test the planner with sample orders before processing real bookings; verify that no load exceeds payload or order capacity and that an empty source load is cancelled.

## 4. Truck inspection pass / gate control

- Complete all eight checklist items truthfully; record defects in inspection notes and keep the pass on HOLD if any check fails.
- Confirm dispatch is blocked unless the pass is cleared for the currently assigned truck.
- Print a sample truck inspection pass and a goods dispatch bill/pass. Confirm the load number, truck registration, driver, order manifest and issue time.
- These are internal factory records. They do not replace a government permit, roadworthiness certificate, tax invoice or other legally required transport paperwork.

## 5. Pilot controls and sign-off

- Use a dedicated test workspace and clearly labelled fictional records for the first walkthrough.
- Have dispatch, warehouse, gate/security and finance users test their own workflows and permissions.
- Review role access and every Row Level Security policy / `SECURITY DEFINER` RPC; set up backups, restore testing, monitoring and audit retention.
- Reconcile a sample booking through stock reservation, dispatch, delivery, invoice, receipt and accounting ledger before using live transactions.
- The project source was syntax-transpiled successfully, and basic connected-database integrity checks passed (posted journal headers balanced; no negative/over-reserved stock; invoice balances matched; no negative payroll net). A full Next.js production build was **not** verified in this environment because dependency installation timed out. Run `npm install`, `npm run lint`, and `npm run build` locally/CI before treating this as production-ready.
