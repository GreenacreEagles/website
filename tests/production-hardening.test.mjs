import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { PAGE_BOUNDS, clampLimit, clampOffset, clampSearch } from "../src/lib/pagination.ts";
import { enforceBodyByteLimit, sanitizeFilename, stripProtectedFields } from "../src/lib/validation.ts";
import { consumeRateLimit, RATE_LIMITS } from "../src/lib/security/rate-limit.ts";
import { PRIVATE_NO_STORE, PUBLIC_HTML_CACHE, isPrivatePath, resolveCacheControl } from "../src/lib/cache.ts";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");

// --- pagination.ts -----------------------------------------------------

test("clampLimit falls back to the resource default for missing or non-positive values", () => {
  assert.equal(clampLimit(undefined, PAGE_BOUNDS.news), PAGE_BOUNDS.news.defaultLimit);
  assert.equal(clampLimit(0, PAGE_BOUNDS.news), PAGE_BOUNDS.news.defaultLimit);
  assert.equal(clampLimit(-5, PAGE_BOUNDS.news), PAGE_BOUNDS.news.defaultLimit);
  assert.equal(clampLimit("not-a-number", PAGE_BOUNDS.news), PAGE_BOUNDS.news.defaultLimit);
});

test("clampLimit never exceeds the per-resource maximum, even for huge requested values", () => {
  assert.equal(clampLimit(999999, PAGE_BOUNDS.wallets), PAGE_BOUNDS.wallets.maxLimit);
  assert.equal(clampLimit(50, PAGE_BOUNDS.wallets), 50);
  assert.equal(clampLimit(30, PAGE_BOUNDS.volunteers), 30);
});

test("clampOffset rejects negative or non-numeric offsets and caps runaway values", () => {
  assert.equal(clampOffset(undefined), 0);
  assert.equal(clampOffset(-10), 0);
  assert.equal(clampOffset("40"), 40);
  assert.equal(clampOffset(999999, 100), 100);
});

test("clampSearch trims, bounds length and rejects non-string input", () => {
  assert.equal(clampSearch("  hello  "), "hello");
  assert.equal(clampSearch(""), null);
  assert.equal(clampSearch("   "), null);
  assert.equal(clampSearch(42), null);
  assert.equal(clampSearch("a".repeat(200), 10).length, 10);
});

// --- validation.ts -------------------------------------------------------

test("sanitizeFilename removes slashes and leading dots so traversal segments cannot form a path", () => {
  const result = sanitizeFilename("../../etc/passwd");
  assert.doesNotMatch(result, /[/\\]/);
  assert.doesNotMatch(result, /^\./);
});

test("sanitizeFilename replaces whitespace and dangerous characters, and enforces a maximum length", () => {
  assert.equal(sanitizeFilename("my file name.pdf"), "my-file-name.pdf");
  assert.doesNotMatch(sanitizeFilename('weird"name<>.txt'), /["<>]/);
  assert.ok(sanitizeFilename("a".repeat(500)).length <= 180);
});

test("sanitizeFilename never returns an empty name", () => {
  assert.equal(sanitizeFilename(""), "upload.bin");
  assert.equal(sanitizeFilename("..."), "upload.bin");
});

test("stripProtectedFields removes protected profile columns and merges a custom blocklist", () => {
  const input = { full_name: "A", role: "admin", wallet_balance_cents: 500, is_super_admin: true, nickname: "Ace" };
  assert.deepEqual(stripProtectedFields(input), { full_name: "A", nickname: "Ace" });
  assert.deepEqual(stripProtectedFields({ full_name: "A", nickname: "Ace" }, ["nickname"]), { full_name: "A" });
});

test("enforceBodyByteLimit rejects requests whose declared content-length exceeds the cap", () => {
  const big = new Request("https://example.com", { method: "POST", headers: { "content-length": "999999" } });
  const rejected = enforceBodyByteLimit(big, 1000);
  assert.ok(rejected);
  assert.equal(rejected.status, 413);
  assert.equal(rejected.headers.get("cache-control"), "private, no-store");

  const small = new Request("https://example.com", { method: "POST", headers: { "content-length": "10" } });
  assert.equal(enforceBodyByteLimit(small, 1000), null);
});

// --- rate-limit.ts ---------------------------------------------------------

test("consumeRateLimit falls back to in-memory limiting and fails closed once a burst exceeds max", async () => {
  const key = `test-key-${crypto.randomUUID()}`;
  const config = { windowSeconds: 60, maxRequests: 3 };
  const results = [];
  for (let i = 0; i < 5; i += 1) {
    results.push(await consumeRateLimit({ supabase: null, limitClass: "generic", key, config }));
  }
  assert.deepEqual(results.slice(0, 3).map((r) => r.allowed), [true, true, true]);
  assert.deepEqual(results.slice(3).map((r) => r.allowed), [false, false]);
  assert.equal(results[4].remaining, 0);
  assert.ok(results[4].retryAfterSeconds > 0);
});

test("consumeRateLimit falls back to memory limiting when the supabase RPC throws, instead of failing open with an exception", async () => {
  const key = `test-key-${crypto.randomUUID()}`;
  const brokenSupabase = { rpc: async () => { throw new Error("network down"); } };
  const result = await consumeRateLimit({ supabase: brokenSupabase, limitClass: "wallet", key });
  assert.equal(result.allowed, true);
  assert.equal(typeof result.remaining, "number");
  assert.equal(result.remaining, RATE_LIMITS.wallet.maxRequests - 1);
});

// --- cache.ts ---------------------------------------------------------------

test("resolveCacheControl always forces private no-store for portal, admin and api paths", () => {
  const req = new Request("https://example.com/portal/dashboard");
  assert.equal(resolveCacheControl({ pathname: "/portal/dashboard", method: "GET", status: 200, request: req }), PRIVATE_NO_STORE);
  assert.equal(resolveCacheControl({ pathname: "/admin/users", method: "GET", status: 200, request: req }), PRIVATE_NO_STORE);
  assert.equal(resolveCacheControl({ pathname: "/api/portal/profile", method: "GET", status: 200, request: req }), PRIVATE_NO_STORE);
  assert.ok(isPrivatePath("/portal/family/"));
  assert.ok(isPrivatePath("/api/wwcc-document"));
});

test("resolveCacheControl allows public caching only for anonymous marketing GET requests", () => {
  const req = new Request("https://example.com/news");
  assert.equal(resolveCacheControl({ pathname: "/", method: "GET", status: 200, request: req }), PUBLIC_HTML_CACHE);
  assert.equal(resolveCacheControl({ pathname: "/news", method: "GET", status: 200, request: req }), PUBLIC_HTML_CACHE);
});

test("resolveCacheControl never caches when auth cookies, Set-Cookie or non-GET methods are involved", () => {
  const cookieRequest = new Request("https://example.com/news", { headers: { cookie: "sb-access-token=abc" } });
  assert.equal(resolveCacheControl({ pathname: "/news", method: "GET", status: 200, request: cookieRequest }), PRIVATE_NO_STORE);

  const plainRequest = new Request("https://example.com/news");
  assert.equal(resolveCacheControl({ pathname: "/news", method: "GET", status: 200, request: plainRequest, setCookie: true }), PRIVATE_NO_STORE);
  assert.equal(resolveCacheControl({ pathname: "/news", method: "POST", status: 200, request: plainRequest }), PRIVATE_NO_STORE);
});

// --- payments.ts / webhook (contract: cloudflare:workers dependency prevents direct import) ---

test("payment provider defaults to manual and the webhook route short-circuits accordingly", () => {
  const source = read("src/lib/payments.ts");
  assert.match(source, /getPaymentProvider = \(context\?/);
  assert.match(source, /\?\? "manual"\)/);
  assert.match(source, /isManualPaymentMode = \(context\?: RuntimeContext\) => getPaymentProvider\(context\) === "manual"/);
  assert.match(source, /manualPaymentDisabledResponse[\s\S]*status: 503/);
  assert.match(source, /disabled: true/);

  const webhook = read("src/pages/api/webhooks/payments.ts");
  assert.match(webhook, /isManualPaymentMode\(context\)/);
  assert.match(webhook, /manualPaymentDisabledResponse\(/);
  assert.match(webhook, /Online payment webhooks are disabled/);
  assert.match(webhook, /paymentWebhookRequired\(context\)/);
});

// --- portal write routes rely on atomic RPCs and rate limiting ---

test("child-account.ts uses the atomic provisioning RPC with compensating auth cleanup on failure", () => {
  const source = read("src/pages/api/portal/child-account.ts");
  assert.match(source, /rpc\("complete_child_account_provisioning"/);
  assert.match(source, /compensateAuthUser/);
  assert.match(source, /auth\.admin\.deleteUser\(authUserId\)/);
  assert.match(source, /limitClass: "child_account"/);
});

test("team-post.ts creates posts through the atomic poll RPC and is rate limited", () => {
  const source = read("src/pages/api/portal/team-post.ts");
  assert.match(source, /rpc\("create_team_post_with_poll"/);
  assert.match(source, /limitClass: "posts"/);
});

test("team-post-reaction.ts toggles likes through the atomic reaction RPC and is rate limited", () => {
  const source = read("src/pages/api/portal/team-post-reaction.ts");
  assert.match(source, /rpc\("set_team_post_reaction"/);
  assert.match(source, /limitClass: "likes"/);
});

// --- newly rate-limited write endpoints (section 2 of the hardening pass) ---

test("newly hardened write endpoints consume the correct rate limit class", () => {
  const expectations = [
    ["src/pages/api/portal/wallet-top-up.ts", "wallet"],
    ["src/pages/api/admin/redeem-voucher.ts", "vouchers"],
    ["src/pages/api/portal/wwcc-submission.ts", "uploads"],
    ["src/pages/api/wwcc-document.ts", "wwcc_document"],
    ["src/pages/api/portal/family-invite.ts", "invitations"],
    ["src/pages/api/admin/reorder.ts", "generic"]
  ];
  for (const [path, limitClass] of expectations) {
    const source = read(path);
    assert.match(source, /consumeRateLimit/, `${path} must call consumeRateLimit`);
    assert.match(source, new RegExp(`limitClass:\\s*"${limitClass}"`), `${path} must use the "${limitClass}" rate limit class`);
  }
});

// --- media.ts upload security polish ---

test("media.ts rejects SVG uploads and never logs file contents in the private upload audit trail", () => {
  const source = read("src/lib/media.ts");
  assert.doesNotMatch(source, /svg/i);
  assert.match(source, /logPrivateUploadAudit/);
  assert.match(source, /sanitizeFilename/);
  const auditFn = source.match(/export const logPrivateUploadAudit[\s\S]*?\n};/)?.[0] ?? "";
  assert.ok(auditFn, "logPrivateUploadAudit helper must exist");
  assert.doesNotMatch(auditFn, /bytes|contentType|object_path|objectKey/);
});

test("putPublicMediaObject stores public media with an immutable long-lived cache header", () => {
  const source = read("src/lib/media-core.ts");
  assert.match(source, /cacheControl: "public, max-age=31536000, immutable"/);
});
