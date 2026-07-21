# Cloudflare Pages Deployment

This project uses GitHub as the source repository only. Cloudflare Pages should build and host the public website and protected portal.

Do not enable GitHub Pages for this repository. Do not add Jekyll, `jekyll-theme-primer`, `_config.yml`, or GitHub Pages workflows.

## Cloudflare Settings

- Framework preset: `Astro`
- Build command: `npm run build`
- Build output directory: `dist`
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

Public marketing/content pages are prerendered into the build output. Protected portal, admin, and API routes run through Cloudflare Pages Functions so authentication and authorization happen server-side.

Cloudflare Pages still uses `dist` as the output directory.

Required runtime bindings:

- `SESSION`: Workers KV binding used by Astro sessions.
- `IMAGES`: Cloudflare Images binding used by the Cloudflare adapter image service when enabled.

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

This keeps the public site fast, portable, and easy for Cloudflare Pages to build.

## Future Admin Direction

The public foundation is now ready for a simple database-backed admin system later:

- Supabase Auth handles secure login.
- Portal/admin routes already run server-side.
- Role and permission checks are centralized in Supabase RLS/RPCs and server route guards.
- Public content still lives in `src/content` while operational workflows are built out.
- Future content tables can support article publishing, social post links, featured updates, media records, and simple editor workflows without changing the public routing model.

Do not add GitHub Pages, Jekyll, or GitHub Pages-specific build steps.
