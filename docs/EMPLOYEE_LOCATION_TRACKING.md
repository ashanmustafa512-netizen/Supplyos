# SupplyOS Employee Location Tracking (Android-first)

## What it does
- Reuses the SupplyOS Employee Android app for both employee work-shift location and assigned delivery-trip tracking.
- Employees must sign in and explicitly tap **Agree & start shift location**. Android shows a persistent location foreground-service notification while the session is active.
- GPS fixes are sent to Supabase about every 15 seconds / 25 metres when Android provides them and the network is available.
- Routes & geofencing displays active employee markers, last received timestamp, accuracy, straight-line distance from the configured factory gate, and `inside`, `nearby`, `outside`, or `unknown` factory geofence state.
- Positions older than 2 minutes are stale. Poor GPS accuracy (>150 m or missing accuracy) sets geofence state to `unknown`, not a false inside/outside result.
- Employees can stop sharing at any time. Managers/dispatchers can end the server session; ask the employee to open the app so it also stops the phone's native service promptly. A rejected background update stops the native task when it next runs.
- Employee location sessions and trip sessions cannot be active at the same time for one account.

## Privacy and work policy
Use only on company-authorized phones/accounts and after giving employees a written notice covering purpose, access, retention, support contact, and working-hour expectations. This implementation collects location only during a session the employee starts, not silently after sign-in and not after the employee ends the shift. Do not use the feature to track employees off-duty. Establish and communicate a retention schedule before production rollout; session rows currently remain for audit and are not automatically deleted.

## Database
Apply `supabase/migrations/20261020190800_employee_shift_location_tracking.sql` followed by `supabase/migrations/20261020191000_employee_location_fix_timestamp.sql` to the same Supabase project as SupplyOS. Together they create `employee_location_sessions`, row-level policies, secured RPCs, indexes, Realtime publication membership, and ensure stale indicators use the GPS fix timestamp rather than merely the time the server received it. These migrations are also applied to the connected development project as part of this implementation.

RPCs:
- `start_employee_location_shift(p_consent_version text)` — records consent and opens a shift.
- `record_employee_location(...)` — accepts only the signed-in employee's active session and computes factory geofence state server-side.
- `stop_employee_location_shift(p_session_id uuid, p_reason text)` — employee stops their own session.
- `admin_stop_employee_location_shift(...)` — owner/admin/manager/dispatcher closes a session.

Direct client writes to the table are not granted. The dispatcher map reads active sessions under RLS and receives Supabase Realtime updates; a 30-second refresh is retained as fallback.

## Android setup
1. Install Node.js LTS, Android Studio/SDK, and a physical Android phone.
2. In `mobile-driver`, copy `.env.example` to `.env` and set the project's Supabase URL and publishable key. Never use a service-role/secret key in the mobile app.
3. Run `npm install`, then `npx expo prebuild`, then `npx expo run:android` for a local development build. Use a signed EAS/Gradle build for managed rollout; Expo Go is not sufficient for background location.
4. Create a separate Supabase Auth account for every employee and add each account to the correct organization membership. Do not share one login across employees; the session is tied to `auth.uid()`.
5. Verify the factory gate latitude/longitude and geofence radius under Routes & geofencing.
6. Give each employee the written notice, explain the persistent notification and stop control, and let them sign in and start a shift themselves.

## Pilot test plan
1. **Consent**: sign in without starting; verify no employee row is created and no position is sent. Cancel the consent dialog and confirm tracking remains off.
2. **Start**: accept consent, grant foreground and background location, verify an active shift appears on the map after the first GPS upload.
3. **Factory geofence**: stand inside the configured radius; check `inside` with acceptable accuracy. Walk outside; check `outside`. Move within the extra 500 m band; check `nearby`. Use an inaccurate/poor signal fix; expect `unknown`.
4. **Background**: lock the screen for 10–15 minutes with location permission set to Allow all the time and battery optimization tested per handset vendor. Verify timestamp advances. Android may throttle/kill apps on some OEMs; document device-specific behavior.
5. **Network outage**: turn mobile data off for several minutes. The map must keep the last position and label it stale after 2 minutes; it must not pretend the employee is still live. Restore data and verify a new fix updates the map. This version does not queue full offline route history.
6. **Stop**: employee taps End shift; verify the row leaves the active map and no further points are accepted. Test manager ending a session; ask employee to reopen the app and verify the background task stops after the rejected update.
7. **Access control**: test as employee A, employee B, and a manager in another organization. Employees should see only their own sessions; authorized managers should see only their organization's sessions; unrelated workspaces must not see employee coordinates.
8. **Trip safety regression**: verify shift start is rejected during an active delivery trip and trip start is rejected during an active shift. Verify truck inspection pass and assignment gates still apply to delivery trips.
9. **Load and battery**: test 25 phones, updates at ~15 seconds / 25 m, screen locked, mobile data, low battery, permissions revoked, app restart, and weak GPS indoors. Measure actual monthly data/battery use before rollout.

## Limitations before production
- A native Android build and physical-device background tests are still required; source code alone cannot prove OEM-specific background reliability.
- Location depends on GPS availability and internet access for live map updates. GPS can determine location without data, but the server cannot receive it until the phone has internet.
- This stores current position and shift-session metadata, not a complete breadcrumb history. Add a separately governed, retention-limited point-history table only if route history is genuinely required.
- A factory geofence indicates proximity, not proof of attendance or work performed. Use attendance, task completion, and manager review as separate records.
