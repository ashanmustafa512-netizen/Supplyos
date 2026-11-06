# SupplyOS factory demo and release checklist

Use this checklist before presenting a live workflow to a factory. The connected Supabase project is a development workspace with demo records; do not use the demo seed in production.

## Routes and fleet visibility

- [ ] Save the factory's actual gate coordinates and a suitable radius (start around 250 m, then tune against GPS accuracy and site layout).
- [ ] Confirm all trucks are listed, including idle and maintenance vehicles; a truck without a fresh GPS fix must be shown as stale/unknown rather than treated as being at the factory.
- [ ] On the phone/device carried by a truck, open Routes, select that truck, grant location permission, and start Live GPS sharing. Keep the page open during the demo.
- [ ] Move or simulate the device position in a controlled test and confirm its marker, factory distance, and inside/nearby/outside status update.
- [ ] Confirm customer stop geofences only use known customer coordinates. Missing or demo/approximate coordinates must be visibly treated as such.

## Dispatch, capacity reuse, and truck pass

- [ ] Approve a booking and plan dispatch. Check the selected truck's order capacity and payload capacity before loading.
- [ ] Add another booking for a compatible locality/nearby route. Confirm it consolidates into an existing planned route only when capacity remains and loading has not started.
- [ ] Test ready-load reuse only with a fresh truck GPS position near the shared factory geofence. Confirm the load returns to planning/loading, the loading checklist resets, the inspection pass is regenerated, and the goods bill pass is refreshed when issued again.
- [ ] Confirm a truck already in transit is never selected for automatic consolidation.
- [ ] Finish loading and confirm the unique truck inspection pass is created automatically.
- [ ] Mark one inspection item incomplete and submit: pass must be HOLD and dispatch must be blocked.
- [ ] Complete all eight checks and submit: pass must be cleared for that exact assigned truck.
- [ ] Reassign the truck after inspection: previous clearance must be invalidated and inspection repeated.
- [ ] Print both the truck inspection/gate pass and the goods bill pass; confirm load number, truck registration, driver, route and order details are legible.

## Other modules: data-integrity smoke checks

- [ ] Bookings: verify approval/rejection status transitions and that only approved bookings are available for dispatch.
- [ ] Inventory: verify receiving a purchase order changes stock only once; check stock reservation/release on dispatch, delivery and cancellation.
- [ ] Accounting: check posted journal entries balance and confirm the invoice/receipt workflow maps to the correct customer and accounts.
- [ ] Sales & recovery: test invoice issue, partial receipt, remaining balance, and task resolution.
- [ ] Payroll: confirm a draft run does not post payment until the approved workflow is completed; check deductions/net pay against the factory's policy.
- [ ] Roles: test each workflow with an owner/admin, manager and staff account, including attempts to access another organization's records.

## Known release gates

- Live location currently depends on browser geolocation from a phone/device travelling with the truck. Mobile browsers may pause when backgrounded or locked. For reliable unattended/24-hour tracking, integrate a supported driver app or truck telematics/GPS provider.
- Factory distance is a straight-line GPS distance, not a road distance or ETA. Map route connectors are visual planning lines, not turn-by-turn routing.
- Truck pass is an internal factory inspection/gate-control record, not a government permit or statutory roadworthiness certificate. Verify the factory's legally required transport documents separately.
- The app's dependencies could not be installed in the build environment during this update (the package install timed out), so a successful `npm run build` is still a required release gate. Run `npm install`, `npm run lint`, and `npm run build` in a network-enabled environment before a production demo.
- Supabase's security advisor still reports authenticated `SECURITY DEFINER` RPCs and performance advisor still reports some foreign-key index recommendations. The RPCs are used for transactional workflows, but every exposed function and role/RLS policy must receive a production security review before onboarding real factories.
