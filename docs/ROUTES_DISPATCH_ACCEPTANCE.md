# SupplyOS fleet, geofencing and dispatch acceptance checklist

Use this checklist with a non-production workspace before factory acceptance or a sales demo. Never use fictional demo records as production shipment data.

## Factory and fleet setup

- [ ] Save the actual dispatch gate address, latitude, longitude and approved radius on **Routes & geofencing**.
- [ ] Compare at least one parked vehicle against a known position and check that the distance-to-factory value is plausible.
- [ ] Pair one authorized, GPS-enabled device per truck and grant location permission. Confirm the route screen updates while the page remains open.
- [ ] Confirm stale GPS reports are visually distinguishable from fresh reports, and that unknown/unreported locations do not get treated as “inside”.
- [ ] Confirm the GPS marker and return distance move on the map/list when the device moves. Straight-line distance is expected; road distance and ETA are not provided by this geofence calculation.

## Capacity-aware dispatch

- [ ] Plan a new booking for the same city/district as a planned load with a truck that has both order capacity and payload capacity available. Confirm SupplyOS consolidates the booking into that existing route.
- [ ] Repeat with a nearby booking with valid coordinates and confirm the locality/distance matching behaves as expected.
- [ ] Confirm an unknown/blank destination is not matched just because two empty values compare equal.
- [ ] With a factory base configured and truck GPS fresher than two minutes, add a matching booking to an eligible ready load. Confirm the load returns to planning/loading, its truck pass is regenerated, and warehouse loading checks must be repeated.
- [ ] Confirm a truck whose GPS is stale, outside the factory geofence, over order capacity or over payload capacity is not selected for ready-load consolidation.
- [ ] Confirm a load already in transit is never consolidated into.

## Inspection and gate pass

- [ ] Finish a load's warehouse loading checklist and confirm a unique truck inspection pass is created automatically.
- [ ] Submit an incomplete inspection and confirm it goes to **HOLD**.
- [ ] Attempt dispatch on HOLD and confirm both the UI and database reject departure.
- [ ] Complete all eight checks and confirm the pass is **CLEARED** for the currently assigned truck.
- [ ] Reassign the truck and confirm the previous inspection is invalidated and cannot clear the newly assigned vehicle.
- [ ] Print a truck inspection pass and a separate goods bill/manifest. Confirm staff understand that these internal SupplyOS documents do not replace official transport permits or legally required paperwork.
- [ ] Confirm a changed manifest refreshes its bill-pass snapshot and prior printed copies are treated as superseded.

## Other module integrity checks performed against the connected development database

- Checked 22 posted accounting journal headers: no debit/credit-total mismatches found.
- Checked product balances: no negative on-hand/reserved stock and no reserved quantity above on-hand stock found.
- Checked sales-invoice balance values: no mismatches against `total_amount - amount_paid` found.
- Checked payroll net-pay values: no negative net-pay lines found.

These database integrity queries are not a replacement for end-to-end acceptance testing. Current GPS sharing depends on a foreground browser/device; reliable background tracking requires a dedicated app or telematics integration. A successful Next.js production build and browser-based workflow test are still required before a live factory deployment.
