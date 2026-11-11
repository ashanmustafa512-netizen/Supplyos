# SupplyOS — Hosting and release checklist

This project is a Next.js 16 App Router application. Deploy the repository root (the folder containing `package.json`), not `src/`, `mobile-admin/`, or `mobile-driver/`.

## Runtime and build settings

- Use Node.js **22.x**. The project pins this in `.nvmrc` and `package.json`.
- Install command: `npm ci`.
- Build command: `npm run build`.
- Start command for a Node host: `npm run start`.
- Framework preset on Vercel: Next.js (normally auto-detected).
- Do not configure a static-export output directory. The app uses server rendering, server actions, Supabase cookies, and Next.js Proxy.

## Required web environment variables

Set these in the hosting provider's server/build environment (Production, Preview, and Development where needed):

```dotenv
NEXT_PUBLIC_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_your_key_here
```

Use the Supabase Project URL and publishable key. Never place a `service_role` or secret key in a `NEXT_PUBLIC_*` variable, a mobile app, or a public repository. Restart/redeploy after changing environment variables.

The root `.env.example` is a placeholder template only. Copy it to `.env.local` for local development and replace both placeholders. Never deploy `.env.local` or commit it.

## Before production

Run from the project root on a machine with npm registry access:

```bash
npm ci
npm run typecheck
npm run lint
npm run build
```

`npm run check` runs all three web release checks. `npm run typecheck` first invokes `next typegen`, which creates the Next.js route types before `tsc` runs. Do not set `typescript.ignoreBuildErrors` or disable TypeScript checks to get a deployment through.

## Supabase database

A successful web build does not create the database schema. Review the migration history in the target Supabase project and apply only migrations that have not already been applied. Do not blindly replay migrations on an existing workspace. Test login, workspace membership, bookings, inventory, dispatch, accounting, payroll, and tracking workflows against a non-production Supabase project before promoting the deployment.

## Optional Android applications

The Expo projects are independent of the web hosting build:

- Install dependencies in `mobile-driver/` before running its `typecheck` script or building the employee app.
- Install dependencies in `mobile-admin/` before running its `typecheck` script or building the WebView wrapper.
- Set the relevant Expo public environment variables before building each app.
- Test Android permissions, background location, notification behavior, and session recovery on real devices. A successful Next.js build does not verify Android behavior.

From the repository root, `npm run check:mobile` runs both mobile TypeScript checks after each mobile app's dependencies have been installed. `npm run check:all` runs web checks/build and both mobile typechecks.

## What this package has and has not verified

The source repair includes static TypeScript/TSX syntax parsing, local import checks, JSON/config checks, and consistency checks between application RPC calls and migration-defined functions/tables. A full `tsc` semantic check, ESLint run, Next.js production build, live Supabase integration test, and Android build still need to run with dependencies and project credentials available. The repair environment could not reach `registry.npmjs.org` during `npm ci`, so those tests are intentionally not reported as passed.
