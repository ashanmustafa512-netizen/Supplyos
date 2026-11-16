# SupplyOS Employee app (Android-first)

This native app is for factory employees who visit shops and submit orders.

## Employee workflow

1. Sign in with an employee (`staff`) account.
2. Agree to work-shift location sharing and grant foreground/background location permissions.
3. Start the work shift. The app shows a persistent Android location notification while the native tracking task is active.
4. Create a booking by selecting an existing shop, product and quantity.
5. View only bookings submitted by the signed-in employee.
6. End the work shift to stop location sharing.

The standalone Customers tab and all truck/dispatch trip-tracking controls have been removed from this app. If a shop is missing, ask the owner or manager to add it from the booking workflow.

## Quick start

1. Copy `.env.example` to `.env` and add the project's Supabase URL and publishable key. Never use a service-role/secret key in the app.
2. Run `npm install`.
3. Run `npx expo prebuild`, then `npx expo run:android` with Android Studio/SDK installed.
4. Use a physical Android phone. Expo Go is not sufficient for background location.
5. Create a separate Supabase Auth login for each employee and add the user to the correct factory organization.
6. Apply the timestamped role-based Supabase migrations under `../supabase/migrations` before using the new employee booking RPCs.

Background location depends on foreground and background permissions, a native build, working GPS, network connectivity for live map updates and Android vendor battery settings. Test the actual phone models before rollout.
