# Greenacre Eagles FC Website

Modern Astro rebuild for the Greenacre Eagles community football club website.

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
5. Add `SITE_URL` as an environment variable when the real domain is confirmed.
6. Deploy from the main production branch after preview approval.

## Admin Editing

This project uses Pages CMS through `.pages.yml`.

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

No database, paid CMS, or custom dashboard is required for this v1.

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

## Notes

The current visual assets include one AI-generated generic football hero and SVG placeholders. Replace these with real Greenacre Eagles imagery before final launch.
