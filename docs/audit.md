# Greenacre Eagles Platform Audit

Date: 2026-07-21

## Repository

- Framework: Astro 7 with Cloudflare adapter.
- Styling: Tailwind CSS with custom club theme.
- Package manager: npm with `package-lock.json`.
- Build command: `npm run build`.
- Output directory: `dist`.
- Public content model: Astro content collections under `src/content`.
- Public pages are prerendered where possible.
- Portal, admin, and API routes are server-rendered for Cloudflare Pages Functions.
- Authentication: Supabase Auth with server-side route guards.
- Supabase integration: browser client for public auth, server client for protected routes and API actions.

## Supabase

- Project: `qzqezldtklimtupajvxf`, region `ap-southeast-2`, Postgres 17.
- Current project status reported by Supabase API: active and healthy.
- Foundation migrations are present for profiles, roles, permissions, seasons, teams, canteen, vouchers, merchandise, volunteers, content, notifications, and audit logs.
- Portal/admin migrations add role request workflows, role assignment RPCs, admin dashboard summaries, role catalog access, and stricter public RPC grants.
- The first portal/admin migration `20260721153000_portal_admin_phase.sql` was applied through Supabase CLI.
- Follow-up fixes in `20260721154500_portal_policy_fixes.sql`, `20260721155000_fix_request_role_rpc.sql`, and `20260721155500_harden_portal_public_rpcs.sql` exist in source and were applied live through Supabase MCP SQL, but Supabase CLI access returned 403 before they could be recorded in remote migration history.
- Active super administrators: 0. The first super administrator still needs to be bootstrapped manually through the trusted SQL process in `docs/super-admin-bootstrap.md`.
- Security advisors: public security-definer RPC warnings have been resolved. Remaining Auth advisory: enable leaked-password protection in Supabase Auth settings.
- Live rollback smoke checks passed for default-user safety, requestable-role requests, blocked super-admin self-request, blocked unauthorized role assignment, and scoped role assignment by a super administrator.

## Cloudflare

- Pages project: `website`.
- Source: GitHub `GreenacreEagles/website`.
- Production branch: `main`.
- Build command: `npm run build`.
- Output directory: `dist`.
- Attached Pages domain: `website-4h5.pages.dev`.
- Custom domains: none attached through Cloudflare Pages.
- Required Pages environment variables: `PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_ANON_KEY`, `SITE_URL`, `NODE_VERSION=22`.
- Runtime: Cloudflare Pages Functions through `@astrojs/cloudflare`.
- Astro sessions require the Cloudflare KV binding named `SESSION`.
- Cloudflare image service support uses the `IMAGES` binding when enabled by the adapter.

## Risks To Replace Or Complete

- Reconcile Supabase CLI permissions and remote migration history before the next normal database push.
- Bootstrap the first super administrator after committee approval.
- Enable leaked-password protection in Supabase Auth settings.
- Confirm Cloudflare Pages bindings for `SESSION` and `IMAGES` before deploying the server-rendered build.
- Attach the production custom domain when ready.
- Canteen, volunteer management, player/staff operations, payments, messaging, and content administration are still future phases.
