import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

/**
 * Refresh the Supabase session before rendering a request.
 *
 * The refreshed cookies must be written to both the forwarded request and
 * the outgoing response. This keeps Server Components and the browser in
 * sync when Supabase rotates an access/refresh token.
 */
export async function updateSession(request: NextRequest): Promise<NextResponse> {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabasePublishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  // Allow the app's setup screen to render before Supabase is configured.
  if (!supabaseUrl || !supabasePublishableKey) {
    return NextResponse.next({ request });
  }

  let response = NextResponse.next({ request });

  const supabase = createServerClient(supabaseUrl, supabasePublishableKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        // Make refreshed cookies available to Server Components in this request.
        cookiesToSet.forEach(({ name, value }) => {
          request.cookies.set(name, value);
        });

        // Recreate the response after mutating request cookies, then persist
        // the same cookies for the browser.
        response = NextResponse.next({ request });
        cookiesToSet.forEach(({ name, value, options }) => {
          response.cookies.set(name, value, options);
        });

      },
    },
  });

  // Do not insert work between client creation and getClaims(): this call
  // refreshes expired tokens and prevents Server Components from seeing stale
  // authentication cookies.
  await supabase.auth.getClaims();

  return response;
}
