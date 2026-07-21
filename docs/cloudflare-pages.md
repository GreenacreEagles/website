# Cloudflare Deployment

This project uses GitHub as the source repository only. Cloudflare should host the public website and protected club portal.

Do not enable GitHub Pages for this repository. Do not add Jekyll, `jekyll-theme-primer`, `_config.yml`, or GitHub Pages workflows.

## Current Production Runtime

The Greenacre Eagles portal contains protected server-rendered routes such as `/portal/`, `/admin/`, and `/api/`. The installed `@astrojs/cloudflare` adapter now targets Cloudflare Workers for this kind of Astro SSR app.

Deploy the full website and portal as a Cloudflare Worker:

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

## Cloudflare Pages Fallback

The existing Cloudflare Pages project can remain as a static public fallback, but it cannot run protected admin and portal routes by itself.

Pages settings:

- Framework preset: `Astro`
- Build command: `npm run build`
- Build output directory: `dist/client`
- Node version: `22`
- Production branch: `main`, unless the repo owner chooses another branch

Current Pages project:

- Project name: `website`
- Pages domain: `https://website-4h5.pages.dev`
- GitHub source: `GreenacreEagles/website`
- Production branch: `main`
- Latest checked production deployment: successful

## Environment Variables

- `SITE_URL`: set this to the production domain once confirmed, for example `https://greenacreeaglesfc.com.au`.
- `PUBLIC_SUPABASE_URL`: Supabase project URL for browser auth and portal calls.
- `PUBLIC_SUPABASE_ANON_KEY`: Supabase publishable/anon key for browser auth and portal calls.
- `NODE_VERSION`: `22`

Production and preview variables have been configured in Cloudflare Pages for the current Pages domain. Update `SITE_URL` after a custom domain is attached.

## Runtime Output

Astro is configured with `@astrojs/cloudflare` and `output: "server"`.

Public marketing/content pages are prerendered into `dist/client`. Protected portal, admin, and API routes run through the Cloudflare Worker server output in `dist/server`.

Required runtime bindings:

- `SESSION`: Workers KV binding used by Astro sessions.

Cloudflare Pages reads these files from `public/` during the build:

- `public/_redirects`
- `public/_headers`

The root `.nojekyll` file is intentionally empty. It is present only as a defensive marker and is not part of the Cloudflare Pages deployment model.

## Current Content Model

The public website is static-first. Editable content lives in Markdown collections under `src/content`:

- `news`
- `weekly-highlights`
- `social-posts`
- `sponsors`
- `fundraisers`
- `events`
- `gallery`
- `teams`
- `announcements`

This keeps the public site fast, portable, and easy to build.

## Future Admin Direction

The public foundation is now ready for a simple database-backed admin system later:

- Supabase Auth handles secure login.
- Portal/admin routes already run server-side.
- Role and permission checks are centralized in Supabase RLS/RPCs and server route guards.
- Public content still lives in `src/content` while operational workflows are built out.
- Future content tables can support article publishing, social post links, featured updates, media records, and simple editor workflows without changing the public routing model.

Do not add GitHub Pages, Jekyll, or GitHub Pages-specific build steps.
