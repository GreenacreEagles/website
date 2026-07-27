import { defineMiddleware } from "astro:middleware";
import { formatServerTimings, recordServerTiming } from "@lib/server-timing";

const privatePrefixes = ["/portal/", "/admin/", "/api/"];
const dynamicPublicPrefixes = ["/news", "/events", "/sponsors", "/social", "/teams", "/merchandise", "/canteen"];

export const onRequest = defineMiddleware(async (context, next) => {
  const startedAt = performance.now();
  const pathname = context.url.pathname;
  const isApiRequest = pathname.startsWith("/api/");

  if (isApiRequest && pathname.length > 5 && pathname.endsWith("/")) {
    const canonicalUrl = new URL(context.url);
    canonicalUrl.pathname = pathname.slice(0, -1);
    return new Response(null, {
      status: 308,
      headers: { "Location": canonicalUrl.pathname + canonicalUrl.search, "Cache-Control": "private, no-store" }
    });
  }

  if (isApiRequest && !["GET", "HEAD", "OPTIONS"].includes(context.request.method)) {
    const origin = context.request.headers.get("origin");
    const fetchSite = context.request.headers.get("sec-fetch-site");
    if (fetchSite === "cross-site" || (origin && new URL(origin).origin !== context.url.origin)) {
      return Response.json({ error: "Cross-site API requests are not allowed.", path: pathname }, { status: 403 });
    }
  }

  let response = await next();
  recordServerTiming(context, "total", startedAt);

  const timings = formatServerTimings(context);
  if (isApiRequest && response.status >= 400 && response.headers.get("content-type")?.includes("text/html")) {
    response = Response.json(
      { error: "API request failed.", path: pathname, method: context.request.method, status: response.status },
      { status: response.status, headers: { "Cache-Control": "private, no-store" } }
    );
  }
  if (timings) response.headers.set("Server-Timing", timings);

  const privateResponse =
    privatePrefixes.some((prefix) => pathname.startsWith(prefix)) ||
    pathname === "/login/" ||
    pathname === "/login" ||
    context.request.headers.has("cookie");

  if (privateResponse) {
    response.headers.set("Cache-Control", "private, no-store");
    return response;
  }

  if (
    context.request.method === "GET" &&
    response.status === 200 &&
    (pathname === "/" || dynamicPublicPrefixes.some((prefix) => pathname.startsWith(prefix)))
  ) {
    response.headers.set("Cache-Control", "public, max-age=30, s-maxage=120, stale-while-revalidate=300");
  }

  return response;
});
