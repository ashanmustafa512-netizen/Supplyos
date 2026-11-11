# SupplyOS Android driver tracking (pilot: 25 trucks)

## What is implemented

- Separate Expo/React Native driver app in `mobile-driver/` with email/password Supabase Auth.
- Trip tracking only starts after a driver taps **Agree & start tracking**, reviews the trip-specific notice, grants foreground and background location permission, and the server confirms the assigned load is `in_transit` with a `cleared` truck inspection pass.
- Android location updates use Expo Location's foreground service and persistent notification, with a target cadence of 15 seconds / 25 metres. Android may throttle delivery due to battery optimization, OS settings, signal or app force-stop; this is a best-effort target, not a guaranteed cadence.
- A session-bound RPC validates the authenticated driver, active driver-to-truck assignment, active trip, coordinate ranges, GPS accuracy and fix timestamp. GPS fixes with accuracy worse than 150 metres can still update the displayed truck position, but the factory geofence is marked `unknown` and customer-stop geofence transitions are not recalculated from that low-confidence fix. It delegates to the existing `set_dispatch_truck_location` RPC so factory distance/geofence and delivery-stop geofence transitions stay on the established path.
- Trip sessions record consent version/time and stop time/reason. Smart route consolidation may reuse a ready truck only when the latest position is sourced from phone/hardware GPS, no more than two minutes old, and GPS accuracy is 150 metres or better; manual coordinates do not qualify for that safety gate. Server triggers end sessions if the load leaves `in_transit`, its truck changes, or the driver assignment is deactivated/changed.
- Dispatcher fleet map receives `dispatch_trucks` updates through Supabase Realtime (RLS remains in force), with the existing 30-second polling refresh as a recovery path. The map's existing two-minute freshness threshold makes delayed locations visible as stale.
- Manager/dispatcher page `/dispatch/tracking` maps one active driver account to each truck.
- Location source and accuracy are stored to allow later hardware-provider integration without changing the UI's location contract.

## Supabase setup

The migrations `20261018112451_phone_gps_trip_tracking.sql`, `20261018112601_tracking_safety_and_geofence_hooks.sql`, `20261018112741_tracking_policy_hardening.sql`, `20261018112836_tracking_workspace_driver_names.sql`, `20261018112851_tracking_driver_role_enforcement.sql`, `20261018113019_tracking_assignment_staff_gate.sql`, `20261018113130_tracking_accuracy_aware_geofence.sql`, and `20261018113227_smart_dispatch_requires_trusted_gps.sql` are included under `supabase/migrations/` and have been applied to the connected project during this implementation. For a different project, apply the normal project migrations in timestamp order.

Create or invite each driver as an authenticated Supabase user and add them to the factory workspace with a permitted workspace role (typically `staff`). Then open **Dispatch → Driver tracking setup** and assign the user to a truck. If the project has no driver-invite UI yet, create the driver in Supabase Auth and add the staff membership through an administrator SQL session, replacing the placeholders:

```sql
insert into public.memberships (organization_id, user_id, role)
values ('YOUR_ORGANIZATION_UUID', 'DRIVER_AUTH_USER_UUID', 'staff')
on conflict (organization_id, user_id) do update set role = 'staff';
```

Only an owner/admin/manager/dispatcher can assign that staff member to a truck. Dispatch the load through the existing workflow and clear the truck inspection pass before the driver can start tracking.

## Run the Android app

1. Install Node.js LTS and Android Studio / Android SDK on the developer workstation.
2. In `mobile-driver/`, copy `.env.example` to `.env` and set `EXPO_PUBLIC_SUPABASE_URL` and `EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. Use only the publishable key; never place a service-role/secret key in a mobile app.
3. Run `npm install` and `npx expo prebuild` (or `npx expo run:android` for a development build). Background location requires a native development/production build; Expo Go is not a suitable release test for the full background service.
4. Run `npx expo run:android` on an actual Android phone. Log in with a dedicated driver account, select an eligible trip, read the consent notice, and grant location permissions. On Android 11+, the user may need to choose “Allow all the time” from the system permission settings. Disable battery optimization for the pilot only if device/OEM testing shows it is required and company policy permits it.
5. Keep the ongoing notification visible while a trip is active. Stop tracking in the app when the trip ends.

## Stale status

- **Live/fresh:** last server-received coordinate is at most 120 seconds old.
- **Stale:** last coordinate is older than 120 seconds.
- **No report:** no location has ever been accepted.
- **Internet is required for live remote tracking, not for GPS to calculate a position.** With mobile data/Wi-Fi off, the phone may still get GPS fixes, but this version cannot upload them to Supabase; dispatch will show the last server-received location as stale. It does not persist a full offline breadcrumb queue. Once connectivity returns, a later GPS callback can restore fresh status. A server rejection that explicitly says the trip/assignment is no longer active stops the native location task on its next callback.

## Pilot acceptance test plan

Use one test truck, one test driver, and a planned safe test route first; expand to all 25 after acceptance.

1. **Auth / tenant isolation:** driver A cannot see driver B's assignments or start B's load. Anonymous requests and a signed-in user without workspace membership are rejected.
2. **Assignment:** assign a driver from `/dispatch/tracking`; verify their driver app shows only their eligible in-transit loads. Deactivate/reassign the driver and verify the old session closes and subsequent location writes are rejected.
3. **Safety gate:** attempt to start before dispatch, without a cleared truck pass, with a cancelled/delivered load, and with a truck assigned to another driver. Every attempt must fail.
4. **Consent:** sign in without starting a trip; verify no background location task runs and no new location writes appear. Start and confirm Android's persistent foreground-service notification is visible.
5. **Background:** send the app to background, lock the screen for 10–15 minutes, and move the phone safely with the truck. Verify map updates arrive and the server timestamp advances. Repeat with battery saver and manufacturer battery controls documented.
6. **Realtime:** open `/routes` as a dispatcher and update GPS from the phone. Confirm the map and distance-to-factory card update without a manual reload; disconnect WebSocket/network and confirm 30-second polling / stale state behavior.
7. **Factory geofence:** configure the single factory gate coordinate and radius. Test a point inside, near, and outside the radius; verify distance and state are recomputed by the server. GPS location must not clear the truck inspection pass or independently authorize dispatch.
8. **Delivery geofence:** move through a geocoded delivery-stop radius and confirm the existing stop transition/event flow remains intact.
9. **Stale / offline:** disable mobile data for over two minutes; dispatch must label the last location stale, not live. Restore network and confirm a new fix restores fresh status. A stale coordinate must not be treated as current proof of truck presence at the factory.
10. **Trip end:** end the trip manually, deliver/cancel the load, and deactivate the assignment in separate tests. Confirm the server session ends, no later point is accepted, and the app stops location updates when it receives an explicit server rejection.
11. **Invalid payload:** test latitude 91, longitude 181, negative accuracy, accuracy above 10 km, low-confidence GPS accuracy above 150 m (factory geofence must remain `unknown`), future timestamps, and fixes older than five minutes; all must be rejected.
12. **Soak / fleet load:** run 25 test devices for at least 60 minutes. Target 15-second / 25-metre updates while moving, track battery/network impact, Supabase Realtime fan-out, database writes, and stale rate. Tune cadence before production rollout.

## Known limitations / release gates

- A full Android build and physical-device background test are not executed in this workspace; these require Android SDK/device access and installed npm dependencies.
- Existing fleet locations were stale before this feature; set the real factory coordinates and onboard driver accounts/assignments before expecting live fleet visibility.
- A browser GPS sharing control remains in Routes as a manual/dev fallback. It is not a substitute for the native driver app.
- Demo truck coordinates are intentionally simulated from the configured factory toward the assigned demo load destination. They use `location_source='manual'` and are labeled as demo/unverified; they are not evidence of real truck movement and cannot satisfy the trusted-GPS dispatch consolidation gate.
- The location payload is a latest-position record, not a complete breadcrumb history. A future route-history feature should store bounded, retention-controlled location points separately.
- Hardware integration can later use `location_source='hardware_gps'` and the same truck position fields, but needs a provider-specific authenticated ingestion endpoint and replay protection.
