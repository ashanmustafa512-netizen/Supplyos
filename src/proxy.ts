import type { NextRequest } from "next/server";
import { updateSession } from "./lib/supabase/proxy";

/**
 * Next.js 16 request proxy.
 *
 * Keep this file alongside `src/app` so the App Router and Proxy use the
 * same source directory. Session refresh and cookie handling live in the
 * Supabase helper to keep this entry point small.
 */
export async function proxy(request: NextRequest) {
  return updateSession(request);
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
