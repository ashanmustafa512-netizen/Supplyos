# START HERE — SupplyOS Complete Project

This folder is the complete SupplyOS web application and includes the source for the employee Android app and the optional admin/dispatch Android wrapper. **Run the website from this folder**, not from either `mobile-*` folder.

## 1. Requirements

- Windows 10/11, macOS, or Linux
- Node.js 22.x LTS (pinned in `.nvmrc` and `package.json` for consistent hosting and local builds)
- npm (included with Node.js)
- An internet connection for the first dependency install

## 2. Start the website

### Windows (easiest)

1. Extract the ZIP completely (do not open/run it from inside the ZIP preview).
2. Open the `supplyos-build` folder.
3. Double-click `START_WINDOWS.bat`.
4. On the first launch it runs `npm ci`; this downloads dependencies and may take a while depending on your connection.
5. Open `http://localhost:3000` when the terminal says the server is ready. Keep the terminal open while using the website.

### Any operating system (terminal)

```bash
cd supplyos-build
npm ci
npm run dev
```

Then open `http://localhost:3000`.

## 3. Verify before hosting

```bash
npm run typecheck
npm run lint
npm run build
```

Or run the same web release checks together with `npm run check`. `typecheck` first runs `next typegen` so the generated Next.js route types exist before TypeScript checks the source. The optional Expo projects are separate installs; run `npm install` inside each `mobile-*` folder, then run `npm run check:mobile` from the root.

For Vercel, import this folder as the project root and use the detected Next.js framework settings. The build command is `npm run build`; install with `npm ci`. Add `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` to the Vercel project's Production, Preview, and Development environments as appropriate. Do not upload `.env.local` to source control.

## 4. What you see before connecting Supabase

The website is designed to open the `/setup` page when no `.env.local` file is configured. That is an intentional setup screen, not a broken build. You can get the local web server running before entering credentials, but sign-in and operational data require a real Supabase project.

To connect it:

1. Open `.env.example` and copy it to a new file named `.env.local` in this same `supplyos-build` folder.
2. In Supabase Dashboard → Project Settings → API, copy the **Project URL** and **publishable key** into `.env.local`:

   ```dotenv
   NEXT_PUBLIC_SUPABASE_URL=https://YOUR_REAL_PROJECT_REF.supabase.co
   NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_your_real_key
   ```

3. Replace both example values with actual values. Do not leave `YOUR_PROJECT_REF`, `your_key`, or any placeholder text in the file.
4. Stop the dev server with `Ctrl+C` and run `npm run dev` again.
5. Apply the database migrations only if your Supabase database still needs them. For an existing SupplyOS database, **do not blindly rerun migrations**; read the database migration section in `README.md` and check which migrations have already been applied.

Never put a Supabase `service_role` or secret key into `NEXT_PUBLIC_*`, the mobile app, or a ZIP shared with other people. Only the publishable key belongs in this client-facing configuration.

## 5. Main website modules

Dashboard, bookings, customers, dispatch, routes/geofencing, stock/warehouse, sales/recovery, accounting, and payroll are part of the Next.js site. The Routes page can display fleet and employee location sessions when the Supabase schema, permissions, factory coordinates, and tracking app have been configured. This ZIP does not create real GPS positions or production credentials automatically.

## 6. Geofencing reliability patch

For the role/workspace bootstrap and factory-coordinate save fix, review `docs/PRODUCTION_GEOFENCING_GUIDE.md` and apply `supabase/migrations/20261028190000_workspace_and_geofence_reliability.sql` only after checking your existing migration history. Then apply `supabase/migrations/20261028190500_accuracy_aware_fleet_gps.sql` for verified GPS updates. Do not blindly replay database migrations.

## 7. Performance update

The dashboard and Bookings analytics use the database-side `supplyos_dashboard_summary` function so monthly totals and low-stock alerts are aggregated in Postgres instead of transferring large record lists. Apply `supabase/migrations/20261111173000_dashboard_summary_performance.sql` once to the target Supabase project after checking its migration history. The Routes map receives normal GPS changes through Realtime; its polling fallback runs every 30 seconds and pauses while the browser tab is hidden.

## 8. Mobile source (optional)

- `mobile-driver/`: native employee location/trip-tracking app. It is separate from the website and needs its own `.env` plus an Android native/cloud build.
- `mobile-admin/`: optional Android WebView wrapper for the deployed website. Set `EXPO_PUBLIC_ADMIN_URL` to your real deployed HTTPS website URL before building it.
- For APK build details, read `ANDROID_APK_BUILDS.md` and the mobile folders' own README files. This package contains source/configuration, not precompiled APK files.

## 9. Troubleshooting

- **`npm` is not recognized:** install Node.js 22 LTS, close and reopen the terminal, then retry.
- **Wrong Node.js version:** run `node -v`; use Node.js 22.x as pinned by `.nvmrc` and `package.json`.
- **`npm ci` fails:** confirm internet access, then run `npm ci --no-audit --no-fund` manually in `supplyos-build`. This environment cannot download npm packages, so dependencies are not pre-bundled in the ZIP.
- **Port 3000 is busy:** stop the other server using that port, or run `npm run dev -- --port 3001` and open `http://localhost:3001`.
- **Setup page keeps showing:** make sure `.env.local` is in the top-level `supplyos-build` folder, uses the exact variable names above, contains real values, and restart the server.
- **Login fails or modules show database errors:** confirm the Supabase URL/key point to the intended project and the required schema migrations have been applied. Starting the Next.js server alone does not create the database.

## Honest validation note

Release verification is documented in `HOSTING_CHECKLIST.md`. The current repair workspace could syntax-parse all 50 TypeScript/TSX files and verify all local imports, but dependency installation was blocked because DNS/network access to `registry.npmjs.org` failed. Therefore, a full semantic TypeScript check, ESLint run, production build, live Supabase test, and Android build cannot honestly be marked as passed here. Run `npm ci` followed by `npm run check` on a machine with npm registry access before production deployment.

