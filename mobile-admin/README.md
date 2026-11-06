# SupplyOS Admin & Dispatch Android app

This is an HTTPS WebView wrapper for the SupplyOS Next.js admin/dispatch web application. The web app must already be deployed; the wrapper does not host the Next.js server itself.

## Configure
1. Copy `.env.example` to `.env`.
2. Set `EXPO_PUBLIC_ADMIN_URL` to the exact deployed HTTPS URL of SupplyOS. Do not use a placeholder.
3. Run `npm install`.

## Build an installable APK
Install EAS CLI (`npm install -g eas-cli`), sign in (`eas login`), and initialize the project (`eas build:configure`) if prompted. Then run `eas build --platform android --profile preview` and download the APK from the build result.

Authentication and admin/dispatch permissions remain enforced by the web app and Supabase. Use HTTPS and never ship a service-role key in the app.
