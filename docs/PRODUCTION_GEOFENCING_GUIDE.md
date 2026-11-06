# SupplyOS geofencing and location tracking — operator guide

This document describes the shipped web workflow and the production steps needed before using location results for attendance, delivery evidence, dispatch decisions, or employee monitoring.

## 1. Set the factory gate point

1. Sign in using a workspace owner, admin, or manager account.
2. Open **Routes & geofencing**.
3. Enter the dispatch gate address, the factory's latitude and longitude in decimal degrees, and a sensible radius.
4. Select **Save shared factory geofence** and wait for the confirmation that echoes the values returned from the database.
5. Reload the page and confirm the coordinate and radius values remain in the form and on the map.

Latitude and longitude are separate decimal-degree fields: latitude must be between −90 and +90; longitude between −180 and +180. Do not swap them. The address is descriptive text; it does not geocode or override the coordinate fields. Six decimal places are normally enough for a gate pin; GPS accuracy, physical gate layout, buildings, and device quality matter more than adding decimal places.

The save operation is workspace-scoped. A database RPC writes the factory coordinates and radius into the current organization's row, logs the update, then recalculates each stored truck position against that factory point. The page uses the values returned by the database rather than only the typed form values. If the RPC or its migration is missing, the form should show an error instead of silently treating the submitted values as saved.

## 2. What geofencing means in SupplyOS

- **Inside:** the calculated distance is no greater than the configured radius.
- **Nearby:** the point is outside the radius but within the next 500 metres.
- **Outside:** the point is farther away than the radius plus the nearby buffer.
- **Unknown:** coordinates or factory configuration are missing, or a GPS fix is too inaccurate to classify reliably.
- **Stale:** the last reported position is older than two minutes. A stale location must not be presented as live, even if its last known state was inside.

Distance is calculated server-side using a spherical (Haversine) distance approximation. It is a straight-line distance, not road distance or ETA. Do not treat a phone GPS point as proof that a person or vehicle crossed a particular physical gate; GPS error and spoofing are possible. Delivery-stop geofences use the customer coordinates separately from the shared factory gate.

## 3. Truck location flow

1. An authorized dispatcher pairs a device/driver with a truck using the existing assignment workflow.
2. The tracking client obtains latitude, longitude, device-reported accuracy, and the fix timestamp.
3. Authenticated GPS updates use `set_dispatch_truck_gps_location`; manual coordinate edits use a separate RPC and are never treated as verified GPS.
4. The server rejects invalid coordinates, accuracy values outside 0–10,000 metres, fixes older than 30 seconds, timestamps more than 30 seconds in the future, and users without an authorized workspace role.
5. PostgreSQL stores the location source, accuracy and server-received timestamp, computes the factory distance/state, and records an audit event. Delivery-stop geofence states/transitions are only updated when the device reports accuracy of 150 metres or better; poorer fixes are saved for diagnostics but do not establish arrival.
6. The Routes screen treats GPS as trusted only while it is no older than two minutes, the source is phone/hardware GPS, and reported accuracy is at most 150 metres.

The browser's **Live GPS sharing** feature only works while the page is open and the browser continues to deliver geolocation fixes. A phone may pause updates when the page is backgrounded or the screen locks. The employee Android app and driver/trip workflow are the intended route for stronger mobile operation, but they still need their own permissions, build, device testing, battery-policy testing, and deployment. For dependable vehicle telemetry, an installed telematics/GPS device integration is usually more suitable than an open browser tab.

## 4. Employee shift tracking and privacy

Employee locations should only be collected for a disclosed, authorized work purpose. Employees should explicitly start the shift/tracking session, be able to stop it, and be told who can view location and how long records are retained. Access is workspace-scoped and role-gated. Use TLS, Supabase Auth, minimal retention, an incident response process, and a written location-data policy before enabling this with real staff. Avoid covert or off-shift tracking.

## 5. Publish/deploy checklist

- Apply the SupplyOS migrations in order on the target Supabase project. For an existing database, check the migration history and current schema first; do not replay the baseline or all additive migrations blindly.
- Apply `supabase/migrations/20261028190000_workspace_and_geofence_reliability.sql` after the existing dispatch, factory-geofence, finance/payroll and employee-location migrations.
- Then apply `supabase/migrations/20261028190500_accuracy_aware_fleet_gps.sql` to add the dedicated accuracy-aware fleet GPS RPC. Verify the exact applied migration history first; do not replay previously applied migrations blindly.
- Check the saved factory coordinates survive a reload and the saved radius matches the database response.
- Test points inside, just outside, and outside the configured radius with known coordinates; verify the classifications around radius boundaries and check a truck with no coordinates remains unknown.
- Test authorized and unauthorized roles; only owner/admin/manager may change the factory gate, and owner/admin/manager/dispatcher may send fleet GPS updates.
- Test GPS permissions denied, low accuracy, stale position, offline device, stopped sessions, reassigned drivers, and revoked access.
- Verify production HTTPS URLs and auth redirect allowlists. Keep the publishable Supabase key in the client environment only; never ship a service-role/secret key to browser or mobile clients.
- Review the necessary privacy notices, data retention period, audit access, security policies, and monitoring before a real factory rollout.
- Run `npm run build`, lint/type checks, SQL migration checks, and end-to-end acceptance tests in the deployment environment before public release.

This project has not been certified or penetration-tested, and the build/deployment has not been validated against the user's live Supabase environment from this source edit. Treat this as an engineering patch and release candidate, not a claim of production certification.
