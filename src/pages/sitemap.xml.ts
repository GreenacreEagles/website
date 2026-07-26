import type { APIRoute } from "astro";
import { createSupabaseServiceClient } from "@lib/supabase/server";
import { getPublicTeams } from "@lib/public-teams";

export const prerender = false;
const staticPaths = [
  "/", "/about/", "/canteen/", "/community/", "/contact/", "/events/", "/gallery/", "/join/",
  "/merchandise/", "/news/", "/social/", "/sponsors/", "/teams/", "/volunteer/"
];
const escapeXml = (value: string) => value.replace(/[<>&'"]/g, (character) =>
  ({ "<": "&lt;", ">": "&gt;", "&": "&amp;", "'": "&apos;", '"': "&quot;" })[character]!
);

export const GET: APIRoute = async (context) => {
  const origin = context.site ?? new URL(context.request.url).origin;
  const { teams } = await getPublicTeams(createSupabaseServiceClient(context), context,);
  const paths = [...staticPaths, ...teams.map((team) => `/teams/${team.slug}/`)];
  const body = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${paths
    .map((path) => `  <url><loc>${escapeXml(new URL(path, origin).toString())}</loc></url>`).join("\n")}\n</urlset>`;
  return new Response(body, { headers: { "content-type": "application/xml; charset=utf-8", "cache-control": "public, max-age=300, s-maxage=900" } });
};
