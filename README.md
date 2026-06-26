# Greenacre Eagles FC Website

Modern Astro rebuild for the Greenacre Eagles community football club website.

This repo uses GitHub as the source repository only. The production target is Cloudflare Pages, not GitHub Pages or Jekyll.

## Stack

- Astro static site
- Tailwind CSS
- Astro content collections
- Pages CMS configuration for Git-based editing
- Local Lucide-style SVG icon component
- Astro sitemap
- Static hosting target: Cloudflare Pages

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

## Cloudflare Pages Deployment

1. Connect this GitHub repo in Cloudflare Pages.
2. Set the framework preset to `Astro`.
3. Build command: `npm run build`.
4. Build output directory: `dist`.
5. Node version: `22` (`.node-version` is included; `NODE_VERSION=22` can also be set in Cloudflare).
6. Add `SITE_URL` as an environment variable when the real domain is confirmed.
7. Deploy from the main production branch after preview approval.

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

- Cloudflare Pages Functions with email forwarding or a notification provider
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
- Keep generated output out of Git; Cloudflare Pages builds `dist/`.
- Future admin options should preserve the static-first model: Git-backed CMS, Cloudflare Pages Functions only for forms or small server-side integrations, and content stored under `src/content`.
