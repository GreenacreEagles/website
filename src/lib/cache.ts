/**
 * Cloudflare Pages-compatible public caching helpers.
 * Never cache authenticated, cookie-bearing, or private routes.
 */

export const PRIVATE_NO_STORE = "private, no-store";
export const PUBLIC_HTML_CACHE = "public, max-age=30, s-maxage=120, stale-while-revalidate=300";
export const PUBLIC_HTML_SHORT = "public, max-age=15, s-maxage=60, stale-while-revalidate=120";
export const FINGERPRINTED_ASSET_CACHE = "public, max-age=31536000, immutable";
export const PUBLIC_MEDIA_CACHE = "public, max-age=86400, s-maxage=604800, stale-while-revalidate=86400";
export const ERROR_CACHE = "public, max-age=0, s-maxage=10";

const privatePrefixes = ["/portal/", "/admin/", "/api/", "/login", "/signup", "/forgot-password", "/reset-password", "/auth/"];
const publicCachePrefixes = ["/", "/news", "/events", "/sponsors", "/social", "/teams", "/merchandise", "/canteen", "/about", "/community", "/gallery", "/join", "/volunteer", "/weekly-highlights"];

export const isPrivatePath = (pathname: string) =>
  privatePrefixes.some((prefix) => pathname === prefix || pathname.startsWith(prefix) || pathname.startsWith(`${prefix}/`));

export const isPublicCacheablePath = (pathname: string) => {
  if (isPrivatePath(pathname)) return false;
  if (pathname === "/") return true;
  return publicCachePrefixes.some((prefix) => prefix !== "/" && (pathname === prefix || pathname.startsWith(`${prefix}/`) || pathname.startsWith(prefix)));
};

export const requestHasAuthCookies = (request: Request) => {
  const cookie = request.headers.get("cookie");
  if (!cookie) return false;
  // Supabase SSR and Astro session cookies indicate personalised state.
  return /sb-|supabase|astro|session|auth/i.test(cookie);
};

export const resolveCacheControl = (options: {
  pathname: string;
  method: string;
  status: number;
  request: Request;
  setCookie?: boolean;
}): string | null => {
  const { pathname, method, status, request, setCookie } = options;
  if (method !== "GET" && method !== "HEAD") return PRIVATE_NO_STORE;
  if (setCookie || requestHasAuthCookies(request) || isPrivatePath(pathname)) return PRIVATE_NO_STORE;
  if (status >= 500) return PRIVATE_NO_STORE;
  if (status >= 400) return ERROR_CACHE;
  if (status !== 200) return PRIVATE_NO_STORE;
  if (!isPublicCacheablePath(pathname)) return null;
  return PUBLIC_HTML_CACHE;
};

/**
 * Attempt Cloudflare Cache API storage for anonymous public HTML.
 * Safe no-op outside Workers or when caches API is unavailable.
 */
export const maybeStoreEdgeCache = async (request: Request, response: Response, pathname: string) => {
  if (request.method !== "GET") return;
  if (requestHasAuthCookies(request) || isPrivatePath(pathname)) return;
  if (response.status !== 200) return;
  if (response.headers.get("set-cookie")) return;
  if (!response.headers.get("cache-control")?.includes("s-maxage")) return;
  try {
    const cache = (globalThis as typeof globalThis & { caches?: { default?: Cache } }).caches?.default;
    if (!cache) return;
    const cacheKey = new Request(request.url, { method: "GET", headers: { accept: request.headers.get("accept") ?? "*/*" } });
    await cache.put(cacheKey, response.clone());
  } catch {
    // Cache API may be unavailable on Pages Free; headers still guide CDN rules.
  }
};

export const maybeMatchEdgeCache = async (request: Request, pathname: string): Promise<Response | null> => {
  if (request.method !== "GET") return null;
  if (requestHasAuthCookies(request) || isPrivatePath(pathname)) return null;
  try {
    const cache = (globalThis as typeof globalThis & { caches?: { default?: Cache } }).caches?.default;
    if (!cache) return null;
    const cacheKey = new Request(request.url, { method: "GET", headers: { accept: request.headers.get("accept") ?? "*/*" } });
    const hit = await cache.match(cacheKey);
    return hit ?? null;
  } catch {
    return null;
  }
};
