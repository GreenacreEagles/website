# Cloudflare Pages Deployment

This project uses GitHub as the source repository only. Cloudflare Pages should build and host the public website.

Do not enable GitHub Pages for this repository. Do not add Jekyll, `jekyll-theme-primer`, `_config.yml`, or GitHub Pages workflows.

## Cloudflare Settings

- Framework preset: `Astro`
- Build command: `npm run build`
- Build output directory: `dist`
- Node version: `22`
- Production branch: `main`, unless the repo owner chooses another branch

## Environment Variables

- `SITE_URL`: set this to the production domain once confirmed, for example `https://greenacreeaglesfc.com.au`.

The site will still build without `SITE_URL`; `astro.config.mjs` includes a production fallback.

## Static Output

Astro generates a static site into `dist/`.

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

The first admin phase should stay simple:

- Secure login through a Git-backed CMS provider or a small Cloudflare-protected admin surface.
- Admins add, edit, publish, and unpublish articles by changing Markdown frontmatter.
- Admins add social post links and thumbnails through `src/content/social-posts`.
- Admins manage homepage featured updates through `src/content/announcements` and `src/content/weekly-highlights`.
- Media uploads should land under `public/media`.

Avoid adding a custom database until there is a clear need. If dynamic features become necessary, prefer Cloudflare Pages Functions for small server-side tasks such as form handling, preview hooks, or authentication glue.
