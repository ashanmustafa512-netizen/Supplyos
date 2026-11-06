# SupplyOS Employee app (Android-first)

The same company-phone app supports two explicit location-sharing modes:

- **Employee work shift:** an employee taps Agree & start shift location, shares location with authorized factory managers during that active shift, and taps End shift to stop.
- **Delivery trip:** an assigned driver can start tracking only for an eligible in-transit load with a cleared truck inspection pass. Dispatch/assignment safety gates remain in force.

Location is never collected merely because someone signs in. Android displays a persistent location notification while background tracking is active. The employee can stop sharing; managers can close a server session. See `../docs/EMPLOYEE_LOCATION_TRACKING.md` for employee privacy, database migration, setup, and test instructions and `../docs/ANDROID_DRIVER_TRACKING.md` for trip-specific details.

## Quick start
1. Copy `.env.example` to `.env` and add the project's Supabase URL and publishable key. Never use a service-role/secret key in the app.
2. Run `npm install`.
3. Run `npx expo prebuild`, then `npx expo run:android` with Android Studio/SDK installed.
4. Use a physical Android phone. Expo Go is not sufficient for background location.
5. Create a separate Supabase Auth login for each employee and add the user to the correct factory organization. Do not share accounts.
6. Apply migration `20261020190800_employee_shift_location_tracking.sql` to the matching Supabase project and verify the factory gate coordinates in Routes & geofencing.

Background location requires foreground and background location permissions, a native build, a working GPS signal, and internet connectivity for live updates to reach the map. Android vendor battery management may interrupt tracking; test the actual phone models before rollout.
