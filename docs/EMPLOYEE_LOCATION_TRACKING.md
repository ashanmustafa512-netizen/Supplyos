# SupplyOS Team Location Tracking (Android-first)

## What it does
- The SupplyOS Team Android app supports both manager and employee accounts.
- A user must sign in and explicitly tap **Agree & start shift location**. Android displays a persistent location foreground-service notification while the session is active.
- GPS fixes are sent to Supabase about every 15 seconds / 25 metres when Android provides them and the network is available.
- The owner/admin Team live locations page shows active manager and employee sessions, last accepted GPS update, accuracy, straight-line distance from the configured factory gate, and geofence state.
- Positions older than 2 minutes are stale. Poor GPS accuracy (>150 m or missing accuracy) sets geofence state to `unknown`.
- The employee or manager can stop sharing at any time. The owner/admin can remotely end an active session.
- A work-shift location session and a legacy delivery tracking session cannot be active at the same time.

## Privacy and work policy
Use only on company-authorized phones/accounts and after giving team members a written notice covering purpose, access, retention, support contact, and working-hour expectations. Location is collected only during a session the user starts, not silently after sign-in and not after the user ends the shift. Do not use this feature to track anyone off-duty. Establish and communicate a retention schedule before production rollout; session rows currently remain for audit and are not automatically deleted.

## Android setup
1. In `mobile-driver`, copy `.env.example` to `.env` and set the project's Supabase URL and publishable key. Never use a service-role/secret key in the mobile app.
2. Run `npm install`, then `npx expo prebuild`, then `npx expo run:android` for a local development build. Expo Go is not sufficient for background location.
3. Create a separate Supabase Auth account for every manager and employee and add each account to the correct organization membership. Do not share one login across team members; each session is tied to `auth.uid()`.
4. Verify the factory gate latitude/longitude and geofence radius on the organization record.
5. Give each team member the written notice, explain the persistent notification and stop control, and let them start a shift themselves.

## Pilot test plan
1. **Consent**: sign in without starting; verify no session row is created and no position is sent. Cancel the consent dialog and confirm tracking remains off.
2. **Start**: accept consent, grant foreground and background location, verify an active shift appears on the owner's map after the first GPS upload.
3. **Factory geofence**: stand inside the configured radius; check `inside` with acceptable accuracy. Walk outside; check `outside`. Move within the extra 500 m band; check `nearby`. Use an inaccurate/poor signal fix; expect `unknown`.
4. **Background**: lock the screen for 10–15 minutes with location permission set to Allow all the time and battery optimization tested per handset vendor. Verify timestamp advances. Android may throttle/kill apps on some OEMs; document device-specific behavior.
5. **Network outage**: turn mobile data off for several minutes. The map must label the last position stale after 2 minutes; it must not pretend the team member is still live. Restore data and verify a new fix updates the map.
6. **Stop**: user taps End shift; verify the row leaves the active map and no further points are accepted. Test owner/admin ending a session.
7. **Access control**: test as employee A, employee B, manager, owner, and a user in another organization. Employees should see only their own sessions; only owner/admin can see the team's coordinates; unrelated workspaces must not see them.

## Limitations before production
- A native Android build and physical-device background tests are still required; source code alone cannot prove OEM-specific background reliability.
- Location depends on GPS availability and internet access for live map updates. GPS can determine location without data, but the server cannot receive it until the phone has internet.
- This stores current position and shift-session metadata, not a complete breadcrumb history. Add a separately governed, retention-limited point-history table only if route history is genuinely required.
- A factory geofence indicates proximity, not proof of attendance or work performed. Use attendance, task completion, and manager review as separate records.
