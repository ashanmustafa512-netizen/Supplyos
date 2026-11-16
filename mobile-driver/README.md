# SupplyOS Team app

Android app for managers and employees to sign in, explicitly consent to work-shift location sharing, and stop sharing when the shift ends.

## Setup
1. Copy `.env.example` to `.env` and set `EXPO_PUBLIC_SUPABASE_URL` and `EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY`.
2. Install dependencies with `npm install`.
3. Build a native Android development app with `npx expo prebuild` and `npx expo run:android`, or use EAS Build.
4. Create a separate SupplyOS Auth account and organization membership for each manager/employee.

Background location requires Android foreground and background location permission. The app shows a persistent notification while tracking. A manager or employee must explicitly start a shift; location updates stop when they end it. Device battery controls, GPS reception and network availability can affect update frequency. The owner sees current and stale shift positions in the SupplyOS Team live locations page.

This app no longer provides truck, driver assignment, dispatch, or delivery-trip tracking.
