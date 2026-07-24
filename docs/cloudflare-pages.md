# Cloudflare Deployment

This project uses GitHub as the source repository only. Cloudflare should host the public website and protected club portal.

Do not enable GitHub Pages for this repository. Do not add Jekyll, `jekyll-theme-primer`, `_config.yml`, or GitHub Pages workflows.

## Current Production Runtime

The Greenacre Eagles portal contains protected server-rendered routes such as `/portal/`, `/admin/`, and `/api/`. The installed `@astrojs/cloudflare` adapter now targets Cloudflare Workers for this kind of Astro SSR app.

The existing Cloudflare Pages project must run in Pages advanced mode. The `postbuild` script copies Astro's generated Cloudflare Worker into `dist/client/_worker.js/index.js`, so the same `website-4h5.pages.dev` domain can serve both prerendered public pages and server-rendered portal/admin routes.

Cloudflare Pages settings:

- Project name: `website`
- Pages domain: `https://website-4h5.pages.dev`
- Framework preset: `Astro`
- Build command: `npm run build`
- Build output directory: `dist/client`
- Node version: `22`
- Compatibility flag: `nodejs_compat`
- Production branch: `main`, unless the repo owner chooses another branch
- Pages Functions: enabled automatically by the `dist/client/_worker.js` directory

Do not remove `scripts/prepare-pages-worker.mjs` or the `postbuild` script. Without the `_worker.js` directory, Cloudflare Pages serves only the static public pages and `/portal/`, `/admin/`, and `/api/` will not work.

The app can also be deployed as a standalone Cloudflare Worker:

- Worker name: `greenacre-eagles-website`
- Compatibility date: `2026-04-15`
- Build command: `npm run build`
- Deploy command: `npm run deploy:worker`
- Worker entry: `dist/server/entry.mjs`
- Static assets directory: `dist/client`
- Static assets binding: `ASSETS`
- Required KV binding: `SESSION`

The root `wrangler.jsonc` supplies build-time Cloudflare settings. Astro writes the deployable Worker config to `dist/server/wrangler.json`, and `npm run deploy:worker` deploys from that generated config. `wrangler deploy` can automatically provision the `SESSION` KV namespace.

Local deploys require Wrangler authentication. Run `wrangler login` in an interactive terminal, or set `CLOUDFLARE_API_TOKEN` with Workers deploy permissions before running `npm run deploy:worker`.

Required runtime variables:

- `SITE_URL`: set this to the active production Worker or custom domain.
- `PUBLIC_SUPABASE_URL`: Supabase project URL for browser auth and portal calls.
- `PUBLIC_SUPABASE_ANON_KEY`: Supabase publishable/anon key for browser auth and portal calls.
- `SUPABASE_SERVICE_ROLE_KEY`: server-only Supabase key used by trusted webhook routes.
- `PAYMENT_WEBHOOK_SECRET`: shared secret expected by `/api/webhooks/payments/`.
- `COMMUNICATION_WORKER_SECRET`: shared secret expected by `/api/workers/communication-outbox/`.
- `PUBLIC_TURNSTILE_SITE_KEY`: public Cloudflare Turnstile site key rendered on login, signup and password reset forms.
- `TURNSTILE_SECRET_KEY`: server-only Cloudflare Turnstile secret used to validate public auth form submissions.

## Environment Variables

- `SITE_URL`: set this to the production domain once confirmed, for example `https://greenacreeaglesfc.com.au`.
- `PUBLIC_SUPABASE_URL`: Supabase project URL for browser auth and portal calls.
- `PUBLIC_SUPABASE_ANON_KEY`: Supabase publishable/anon key for browser auth and portal calls.
- `SUPABASE_SERVICE_ROLE_KEY`: server-only Supabase key used by trusted webhook routes.
- `PAYMENT_WEBHOOK_SECRET`: long random shared secret sent by payment provider webhook configuration.
- `COMMUNICATION_WORKER_SECRET`: long random shared secret sent by the scheduled email/SMS delivery worker.
- `PUBLIC_TURNSTILE_SITE_KEY`: Cloudflare Turnstile widget site key for the production hostname.
- `TURNSTILE_SECRET_KEY`: Cloudflare Turnstile secret key. When unset, Turnstile validation is disabled so local development still works.
- `NODE_VERSION`: `22`

Production and preview variables have been configured in Cloudflare Pages for the current Pages domain. Update `SITE_URL` after a custom domain is attached.

## Runtime Output

Astro is configured with `@astrojs/cloudflare` and `output: "server"`.

Most public marketing pages are prerendered into `dist/client`. Database-backed public content routes such as `/`, `/news/`, `/news/[slug]/` and `/sponsors/` run through the Cloudflare Worker so they can read published Supabase articles, announcements and sponsor records at request time. Protected portal, admin, and API routes also run through the Worker entry copied to `dist/client/_worker.js/index.js`.

Required runtime bindings:

- `SESSION`: Workers KV binding used by Astro sessions. Configure this in Cloudflare Pages production and preview Functions bindings.

Cloudflare Pages reads these files from `public/` during the build:

- `public/_redirects`
- `public/_headers`

The root `.nojekyll` file is intentionally empty. It is present only as a defensive marker and is not part of the Cloudflare Pages deployment model.

## Current Content Model

The public website uses a hybrid content model. Published Supabase rows are used first for public articles, homepage announcements and sponsors. Markdown collections under `src/content` remain as fallback content and still power static-only sections:

- `news`
- `weekly-highlights`
- `social-posts`
- `sponsors`
- `fundraisers`
- `events`
- `gallery`
- `teams`
- `announcements`

This keeps the public site portable while allowing content editors to publish news, announcements and sponsor records through the admin portal.

## Admin Direction

The public foundation now supports database-backed publishing for selected editable sections:

- Supabase Auth handles secure login.
- Portal/admin routes already run server-side.
- Role and permission checks are centralized in Supabase RLS/RPCs and server route guards.
- Public article, announcement and sponsor publishing is available through `/admin/content/` and `/admin/sponsors/`.
- Notification preferences and the communication outbox are database-backed; an external provider worker should use `/api/workers/communication-outbox/` to claim and complete email/SMS jobs.
- Login, signup and password reset forms render Cloudflare Turnstile when `PUBLIC_TURNSTILE_SITE_KEY` is set and enforce server-side Siteverify validation when `TURNSTILE_SECRET_KEY` is set.
- Markdown remains available for seeded or static sections such as teams, galleries, events, weekly highlights and fundraisers.

Do not add GitHub Pages, Jekyll, or GitHub Pages-specific build steps.
