import { defineMiddleware } from "astro:middleware";
import { formatServerTimings, recordServerTiming } from "@lib/server-timing";

const privatePrefixes = ["/portal/", "/admin/", "/api/"];
const dynamicPublicPrefixes = ["/news", "/events", "/sponsors", "/social", "/teams", "/merchandise", "/canteen"];

export const onRequest = defineMiddleware(async (context, next) => {
  const startedAt = performance.now();
  const response = await next();
  recordServerTiming(context, "total", startedAt);

  const timings = formatServerTimings(context);
  if (timings) response.headers.set("Server-Timing", timings);

  const pathname = context.url.pathname;
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
