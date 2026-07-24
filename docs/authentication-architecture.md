# Authentication Architecture

The Greenacre Eagles portal uses Supabase Auth with Astro server-rendered routes on Cloudflare Pages.

## Client And Server Split

- Browser auth helpers live in `src/lib/supabase/browser.ts`.
- Server auth helpers live in `src/lib/supabase/server.ts`.
- `src/lib/supabaseClient.ts` only re-exports browser-safe helpers for older imports.

Do not put service-role keys in browser code, public environment variables, Astro components, or bundled client scripts.

## Route Protection

Protected pages use server-side guards from `src/lib/auth/guards.ts`:

- `requireUser` protects normal portal pages.
- `requireAdmin` protects admin pages.
- `requirePermission` protects permission-specific workflows.

The session loader in `src/lib/auth/session.ts` validates the Supabase user with `auth.getUser()`, reads the profile, reads active role assignments, and asks the database for effective permissions.

## Cookies

Supabase SSR cookies are read from incoming request headers and written by API/SSR responses. Cookies are configured as HTTP-only, secure, same-site lax cookies with path `/`.

## Signup Safety

New signups are provisioned as general users. Public signup metadata cannot grant admin permissions or super-administrator access.

Public sign in, signup and password reset submissions support Cloudflare Turnstile. The widget renders when `PUBLIC_TURNSTILE_SITE_KEY` is configured, and the server validates `cf-turnstile-response` with Cloudflare Siteverify before calling Supabase Auth when `TURNSTILE_SECRET_KEY` is configured.
