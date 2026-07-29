import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { verifyTurnstileToken } from "../src/lib/security/turnstile-core.ts";
import { runSignInFlow } from "../src/lib/auth/signin-flow.ts";

const productionHosts = new Set(["greenacreeaglesfc.com", "www.greenacreeaglesfc.com"]);
const siteverify = (payload, status = 200) => async () => new Response(JSON.stringify(payload), {
  status,
  headers: { "Content-Type": "application/json" }
});

const credentialsForm = (returnTo = "/portal/") => {
  const form = new FormData();
  form.set("email", "member@example.com");
  form.set("password", "not-placed-in-a-url");
  form.set("returnTo", returnTo);
  form.set("cf-turnstile-response", "test-token");
  return form;
};

test("missing verification token fails before authentication", async () => {
  const result = await verifyTurnstileToken({
    secret: "test-secret",
    token: null,
    expectedAction: "signin",
    expectedHostnames: productionHosts
  });
  assert.equal(result.success, false);
  assert.equal(result.reason, "missing-token");
});

test("invalid verification token is rejected", async () => {
  const result = await verifyTurnstileToken({
    secret: "test-secret",
    token: "invalid-token",
    expectedAction: "signin",
    expectedHostnames: productionHosts,
    fetcher: siteverify({ success: false, "error-codes": ["invalid-input-response"] })
  });
  assert.equal(result.success, false);
  assert.equal(result.reason, "invalid-token");
});

test("expired or duplicate token gets a controlled retry message", async () => {
  const result = await verifyTurnstileToken({
    secret: "test-secret",
    token: "expired-token",
    expectedAction: "signin",
    expectedHostnames: productionHosts,
    fetcher: siteverify({ success: false, "error-codes": ["timeout-or-duplicate"] })
  });
  assert.equal(result.success, false);
  assert.equal(result.reason, "expired-token");
  assert.match(result.error ?? "", /expired/i);
});

test("valid production Turnstile response passes action and hostname checks", async () => {
  const result = await verifyTurnstileToken({
    secret: "test-secret",
    token: "valid-token",
    expectedAction: "signin",
    expectedHostnames: productionHosts,
    fetcher: siteverify({ success: true, action: "signin", hostname: "greenacreeaglesfc.com" })
  });
  assert.deepEqual(result, { success: true });
});

test("wrong action or hostname is rejected", async () => {
  const wrongAction = await verifyTurnstileToken({
    secret: "test-secret",
    token: "valid-token",
    expectedAction: "signin",
    expectedHostnames: productionHosts,
    fetcher: siteverify({ success: true, action: "signup", hostname: "greenacreeaglesfc.com" })
  });
  const wrongHost = await verifyTurnstileToken({
    secret: "test-secret",
    token: "valid-token",
    expectedAction: "signin",
    expectedHostnames: productionHosts,
    fetcher: siteverify({ success: true, action: "signin", hostname: "website-4h5.pages.dev" })
  });
  assert.equal(wrongAction.reason, "action-mismatch");
  assert.equal(wrongHost.reason, "hostname-mismatch");
});

test("invalid email or password returns one safe message", async () => {
  const result = await runSignInFlow(credentialsForm(), {
    verify: async () => ({ success: true }),
    signIn: async () => ({ success: false })
  });
  assert.equal(result.success, false);
  assert.equal(result.status, 303);
  assert.match(result.error, /sign in failed/i);
  assert.doesNotMatch(result.error, /member@example|not-placed-in-a-url/);
});

test("successful sign-in redirects to portal with status 303", async () => {
  let submitted;
  const result = await runSignInFlow(credentialsForm(), {
    verify: async () => ({ success: true }),
    signIn: async (credentials) => {
      submitted = credentials;
      return { success: true };
    }
  });
  assert.deepEqual(result, { success: true, status: 303, location: "/portal/" });
  assert.deepEqual(submitted, { email: "member@example.com", password: "not-placed-in-a-url" });
});

test("external and non-portal return targets are not allowed", async () => {
  for (const returnTo of ["https://evil.example/", "//evil.example/", "/api/auth/signin", "/login/"]) {
    const result = await runSignInFlow(credentialsForm(returnTo), {
      verify: async () => ({ success: true }),
      signIn: async () => ({ success: true })
    });
    assert.equal(result.success, true);
    assert.equal(result.location, "/portal/");
    assert.doesNotMatch(result.location, /evil|password|member%40|member@/);
  }
});

test("password recovery uses a token-hash SSR confirmation flow", async () => {
  const { parseEmailOtpType, confirmationDestination } = await import("../src/lib/auth/email-links.ts");
  assert.equal(parseEmailOtpType("recovery"), "recovery");
  assert.equal(parseEmailOtpType("email"), "email");
  for (const value of [null, "invite", "magiclink", "https://evil.example/"]) assert.equal(parseEmailOtpType(value), null);
  assert.equal(confirmationDestination("recovery"), "/reset-password/");
  assert.match(confirmationDestination("email"), /^\/login\/\?success=/);
  assert.doesNotMatch(confirmationDestination("email"), /token|evil|https?:/);
});

test("recovery password validation rejects weak and mismatched passwords", async () => {
  const { validateRecoveryPasswords } = await import("../src/lib/auth/password-recovery.ts");
  assert.equal(validateRecoveryPasswords({ password: "short", confirmPassword: "short" }).success, false);
  const mismatch = validateRecoveryPasswords({ password: "long-enough", confirmPassword: "different-value" });
  assert.equal(mismatch.success, false);
  assert.match(mismatch.error.issues[0].message, /match/i);
  assert.equal(validateRecoveryPasswords({ password: "long-enough", confirmPassword: "long-enough" }).success, true);
});

test("auth pages and handlers retain the secure recovery contract", () => {
  const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
  const requestPage = read("src/pages/forgot-password.astro");
  const resetPage = read("src/pages/reset-password.astro");
  const requestRoute = read("src/pages/api/auth/reset-password.ts");
  const confirmRoute = read("src/pages/auth/confirm.ts");
  const updateRoute = read("src/pages/api/auth/update-password.ts");
  const signupRoute = read("src/pages/api/auth/signup.ts");
  assert.match(requestPage, /action="\/api\/auth\/reset-password"/);
  assert.match(requestRoute, /resetPasswordForEmail/);
  assert.match(requestRoute, /\/auth\/confirm/);
  assert.match(requestRoute, /If an account exists for that email/);
  assert.match(confirmRoute, /verifyOtp\(\{ token_hash: tokenHash, type \}\)/);
  assert.match(confirmRoute, /gefc-password-recovery/);
  assert.doesNotMatch(confirmRoute, /searchParams\.get\("next"\)/);
  assert.match(resetPage, /Choose a new password/);
  assert.match(resetPage, /action="\/api\/auth\/update-password"/);
  assert.doesNotMatch(resetPage, /action="\/api\/auth\/signin"|action="\/api\/auth\/signup"/);
  assert.match(updateRoute, /auth\.getUser\(\)/);
  assert.match(updateRoute, /auth\.updateUser\(\{ password:/);
  assert.match(updateRoute, /signOut\(\{ scope: "global" \}\)/);
  assert.match(signupRoute, /\/auth\/confirm/);
});

test("auth email templates use supported token-hash links without external redirects", () => {
  const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
  const recovery = read("supabase/templates/recovery.html");
  const confirmation = read("supabase/templates/confirmation.html");
  assert.match(recovery, /\{\{ \.SiteURL \}\}\/auth\/confirm\?token_hash=\{\{ \.TokenHash \}\}&type=recovery/);
  assert.match(confirmation, /\{\{ \.SiteURL \}\}\/auth\/confirm\?token_hash=\{\{ \.TokenHash \}\}&type=email/);
  for (const template of [recovery, confirmation]) {
    assert.doesNotMatch(template, /\.ConfirmationURL|\.RedirectTo|\|\s*[a-z]/i);
    assert.doesNotMatch(template, /pages\.dev|workers\.dev|localhost/);
  }
});
