# Greenacre Eagles FC Website

Modern Astro rebuild for the Greenacre Eagles community football club website.

This repo uses GitHub as the source repository only. The production target is Cloudflare, not GitHub Pages or Jekyll.

## Stack

- Astro static-first website with server-rendered portal routes
- Tailwind CSS
- Astro content collections
- Pages CMS configuration for Git-based editing
- Local Lucide-style SVG icon component
- Astro sitemap
- Hosting target: Cloudflare Workers, with Cloudflare Pages available as a static public fallback

## Local Development

```bash
npm install
npm run dev
```

The dev server usually runs at `http://localhost:4321`.

## Build

```bash
npm run build
```

Static output is generated in `dist/`.

## Cloudflare Deployment

The protected portal and admin routes need the Astro server build, so the full app is deployed as a Cloudflare Worker.

```bash
npm run deploy:worker
```

Before deploying locally, authenticate Wrangler with `wrangler login` or set `CLOUDFLARE_API_TOKEN`.

Worker settings:

- Worker name: `greenacre-eagles-website`
- Build command: `npm run build`
- Deploy command: `npm run deploy:worker`
- Worker entry: `dist/server/entry.mjs`
- Static assets directory: `dist/client`
- Required KV binding: `SESSION`
- Runtime config: `wrangler.jsonc`

The existing Cloudflare Pages project can stay connected as a static public fallback. Its output directory must be `dist/client`. Pages alone will not serve `/portal/`, `/admin/`, or `/api/` routes.

GitHub Pages should remain disabled for this repo. There is no Jekyll configuration, and `.nojekyll` is included only as a defensive signal.

Cloudflare-specific static hosting files:

- `public/_redirects` for Pages redirects.
- `public/_headers` for baseline security headers and static asset caching.

See `docs/cloudflare-pages.md` for the full deployment and future admin direction.

## Admin Editing

This project is structured for a simple Git-based admin/content system. The current candidate is Pages CMS through `.pages.yml`.

Admins can edit:

- News articles
- Weekly highlights
- Featured social posts
- Sponsors
- Fundraisers
- Events
- Gallery items
- Team information
- Club announcements

Pages CMS setup requires a GitHub repository owner to connect the repo at `https://app.pagescms.org/` and grant access to approved editors. CMS edits commit changes back to GitHub, then Cloudflare Pages rebuilds the static site.

No database, paid CMS, or custom dashboard is required for this v1. Editors update Markdown and media in GitHub through the CMS; Cloudflare Pages rebuilds and deploys the static site.

Future admin work should support secure login, article publishing/unpublishing, social post links, and featured homepage updates without changing the public static-first architecture.

## Content Folders

```text
src/content/news
src/content/weekly-highlights
src/content/social-posts
src/content/sponsors
src/content/fundraisers
src/content/events
src/content/gallery
src/content/teams
src/content/announcements
```

Shared site settings live in `src/data/site.ts`.

## Forms

The v1 forms use `mailto:` so the UI is present without a paid service. Best next options for production are:

- Cloudflare Workers routes with email forwarding or a notification provider
- Formspree free tier for a quick managed option
- Google Forms for a lightweight no-code option
- Netlify Forms only if the site moves to Netlify

## Real Content Needed

- Official club logo and brand files
- Real club photos and video thumbnails
- Exact social links
- Real contact email and phone
- Official registration link
- Confirmed team names, coaches, and training times
- Fixture/results source
- Sponsor logos, names, links, and tiers
- Fundraiser links and payment/donation destination
- Club history and committee-approved copy

## Deployment Notes

- Do not add GitHub Pages workflows or Jekyll plugins.
- Keep generated output out of Git; Cloudflare builds `dist/`.
- Future admin options should preserve the static-first public model while using Supabase and server-rendered Worker routes for authenticated club operations.
