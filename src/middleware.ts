import { defineMiddleware } from "astro:middleware";
import { formatServerTimings, recordServerTiming } from "@lib/server-timing";
import { getConfiguredSiteOrigin } from "@lib/site-url";
import { PRIVATE_NO_STORE, isPublicCacheablePath, maybeMatchEdgeCache, maybeStoreEdgeCache, requestHasAuthCookies, resolveCacheControl } from "@lib/cache";

const productionPagesHost = "website-4h5.pages.dev";
const contentSecurityPolicy = [
  "default-src 'self'",
  "base-uri 'self'",
  "object-src 'none'",
  "frame-ancestors 'self'",
  "form-action 'self'",
  "script-src 'self' 'unsafe-inline' https://challenges.cloudflare.com",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: https:",
  "font-src 'self' data:",
  "frame-src https://challenges.cloudflare.com",
  "connect-src 'self' https://*.supabase.co https://challenges.cloudflare.com",
  "upgrade-insecure-requests"
].join("; ");

const applySecurityHeaders = (response: Response, isHttps: boolean) => {
  response.headers.set("Content-Security-Policy", contentSecurityPolicy);
  response.headers.set("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
  response.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  response.headers.set("X-Content-Type-Options", "nosniff");
  response.headers.set("X-Frame-Options", "SAMEORIGIN");
  if (isHttps) response.headers.set("Strict-Transport-Security", "max-age=31536000");
  return response;
};

const redirectResponse = (location: string, status: 303 | 308, isHttps: boolean) =>
  applySecurityHeaders(new Response(null, { status, headers: { Location: location, "Cache-Control": "private, no-store" } }), isHttps);

export const onRequest = defineMiddleware(async (context, next) => {
  const startedAt = performance.now();
  const pathname = context.url.pathname;
  const isApiRequest = pathname.startsWith("/api/");
  const isHttps = context.url.protocol === "https:";
  const canonicalOrigin = getConfiguredSiteOrigin(context);

  if (context.url.hostname === productionPagesHost && canonicalOrigin !== context.url.origin) {
    if (["GET", "HEAD"].includes(context.request.method)) {
      return redirectResponse(`${canonicalOrigin}${pathname}${context.url.search}`, 308, isHttps);
    }
    if (pathname.startsWith("/api/auth/")) {
      return redirectResponse(`${canonicalOrigin}/login/?error=Please+sign+in+on+the+official+club+website.`, 303, isHttps);
    }
  }

  if (isApiRequest && pathname.length > 5 && pathname.endsWith("/")) {
    const canonicalUrl = new URL(context.url);
    canonicalUrl.pathname = pathname.slice(0, -1);
    return redirectResponse(canonicalUrl.pathname + canonicalUrl.search, 308, isHttps);
  }

  if (isApiRequest && !["GET", "HEAD", "OPTIONS"].includes(context.request.method)) {
    const origin = context.request.headers.get("origin");
    const fetchSite = context.request.headers.get("sec-fetch-site");
    if (fetchSite === "cross-site" || (origin && new URL(origin).origin !== context.url.origin)) {
      return applySecurityHeaders(Response.json(
        { error: "Cross-site API requests are not allowed.", path: pathname },
        { status: 403, headers: { "Cache-Control": "private, no-store" } }
      ), isHttps);
    }
  }

  const cacheEligible = context.request.method === "GET" && isPublicCacheablePath(pathname) && !requestHasAuthCookies(context.request);
  if (cacheEligible) {
    const cached = await maybeMatchEdgeCache(context.request, pathname);
    if (cached) {
      recordServerTiming(context, "edge-cache-hit", startedAt);
      const hitResponse = new Response(cached.body, cached);
      const timings = formatServerTimings(context);
      if (timings) hitResponse.headers.set("Server-Timing", timings);
      return applySecurityHeaders(hitResponse, isHttps);
    }
  }

  let response = await next();
  recordServerTiming(context, "total", startedAt);
  applySecurityHeaders(response, isHttps);

  const timings = formatServerTimings(context);
  if (
    isApiRequest &&
    context.request.method === "GET" &&
    context.request.headers.get("sec-fetch-mode") === "navigate" &&
    response.status === 404
  ) {
    const fallback = pathname.startsWith("/api/admin/")
      ? "/admin/"
      : pathname.startsWith("/api/portal/")
        ? "/portal/"
        : pathname.startsWith("/api/auth/")
          ? "/login/"
          : "/";
    let destination = fallback;
    const referer = context.request.headers.get("referer");
    if (referer) {
      try {
        const refererUrl = new URL(referer);
        if (refererUrl.origin === context.url.origin && !refererUrl.pathname.startsWith("/api/")) {
          destination = refererUrl.pathname + refererUrl.search;
        }
      } catch {
        // Ignore malformed Referer headers and use the section fallback.
      }
    }
    return redirectResponse(destination, 303, isHttps);
  }
  if (isApiRequest && response.status >= 400 && response.headers.get("content-type")?.includes("text/html")) {
    response = applySecurityHeaders(Response.json(
      { error: "API request failed.", path: pathname, method: context.request.method, status: response.status },
      { status: response.status, headers: { "Cache-Control": "private, no-store" } }
    ), isHttps);
  }
  if (timings) response.headers.set("Server-Timing", timings);

  const hasSetCookie = Boolean(response.headers.get("set-cookie"));
  const cacheControl = resolveCacheControl({
    pathname,
    method: context.request.method,
    status: response.status,
    request: context.request,
    setCookie: hasSetCookie
  });
  if (cacheControl) response.headers.set("Cache-Control", cacheControl);

  if (!hasSetCookie && cacheControl && cacheControl !== PRIVATE_NO_STORE) {
    await maybeStoreEdgeCache(context.request, response, pathname);
  }

  return response;
});