import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const middleware = read("src/middleware.ts");
const cache = read("src/lib/cache.ts");

test("cache.ts defines a private no-store constant and treats portal/admin/api as always-private prefixes", () => {
  assert.match(cache, /PRIVATE_NO_STORE = "private, no-store"/);
  assert.match(cache, /privatePrefixes = \[[^\]]*"\/portal\/"[^\]]*\]/);
  assert.match(cache, /privatePrefixes = \[[^\]]*"\/admin\/"[^\]]*\]/);
  assert.match(cache, /privatePrefixes = \[[^\]]*"\/api\/"[^\]]*\]/);
});

test("cache.ts grants the homepage and public marketing paths a shared s-maxage", () => {
  assert.match(cache, /PUBLIC_HTML_CACHE = "public, max-age=\d+, s-maxage=\d+/);
  assert.match(cache, /isPublicCacheablePath = [\s\S]*?pathname === "\/"/);
});

test("resolveCacheControl forces private no-store whenever Set-Cookie, auth cookies or a private prefix are present", () => {
  assert.match(cache, /if \(setCookie \|\| requestHasAuthCookies\(request\) \|\| isPrivatePath\(pathname\)\) return PRIVATE_NO_STORE;/);
});

test("resolveCacheControl only returns the public HTML cache policy for cacheable anonymous GETs", () => {
  assert.match(cache, /if \(!isPublicCacheablePath\(pathname\)\) return null;/);
  assert.match(cache, /return PUBLIC_HTML_CACHE;/);
});

test("middleware imports and applies resolveCacheControl to every response", () => {
  assert.match(middleware, /import \{[^}]*resolveCacheControl[^}]*\} from "@lib\/cache";/);
  assert.match(middleware, /const cacheControl = resolveCacheControl\(\{/);
  assert.match(middleware, /pathname,\s*method: context\.request\.method,\s*status: response\.status,\s*request: context\.request,\s*setCookie: hasSetCookie/);
  assert.match(middleware, /if \(cacheControl\) response\.headers\.set\("Cache-Control", cacheControl\);/);
});

test("middleware only stores anonymous, cookie-free responses in the edge cache, never private ones", () => {
  assert.match(middleware, /if \(!hasSetCookie && cacheControl && cacheControl !== PRIVATE_NO_STORE\) \{/);
  assert.match(middleware, /await maybeStoreEdgeCache\(context\.request, response, pathname\);/);
});

test("middleware checks isPublicCacheablePath and requestHasAuthCookies before ever attempting an edge cache read", () => {
  assert.match(middleware, /const cacheEligible = context\.request\.method === "GET" && isPublicCacheablePath\(pathname\) && !requestHasAuthCookies\(context\.request\);/);
  assert.match(middleware, /if \(cacheEligible\) \{/);
});
