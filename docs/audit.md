# Greenacre Eagles Platform Audit

Date: 2026-07-21

## Repository

- Framework: Astro 7 static site.
- Styling: Tailwind CSS with custom club theme.
- Package manager: npm with `package-lock.json`.
- Build command: `npm run build`.
- Output directory: `dist`.
- Current public content model: Astro content collections under `src/content`.
- Authentication before this phase: none.
- Supabase integration before this phase: none in source, no migrations.
- Cloudflare runtime before this phase: Cloudflare Pages static deployment, no Pages Functions.

## Supabase

- Project: `qzqezldtklimtupajvxf`, region `ap-southeast-2`.
- CLI version checked: `2.105.0`.
- Project status reported by Supabase API: `INACTIVE`.
- Public application tables before this phase: none.
- Auth users: 0.
- Storage buckets: none.
- Edge Functions: none.
- Advisors: no security or performance lints reported before schema creation.
- Noted Auth logs: Supabase GoTrue warnings for deprecated `GOTRUE_JWT_ADMIN_GROUP_NAME` and `GOTRUE_JWT_DEFAULT_GROUP_NAME`.

## Cloudflare

- Pages project: `website`.
- Source: GitHub `GreenacreEagles/website`.
- Production branch: `main`.
- Build command: `npm run build`.
- Output directory: `dist`.
- Latest deployment status: success.
- Attached Pages domain: `website-4h5.pages.dev`.
- Custom domains: none attached through Cloudflare Pages.
- Environment variables: none configured in Pages.
- Pages Functions: not in use.
- Zones in connected account: none returned.
- Wrangler: not installed in the project.

## Risks To Replace Or Complete

- The public site canonical fallback points at `https://greenacreeaglesfc.com.au`, but Cloudflare currently serves only `website-4h5.pages.dev`.
- Forms use `mailto:` and need protected server handling before production operations.
- The current `/admin/` page is informational only.
- There is no live auth, member portal, canteen, voucher, volunteer, merchandise, or admin workflow yet.
- Production operations require RLS-backed Supabase schema plus server-side workflows before launch.
