// Shared configuration for the k6 staging load-test suite.
//
// STAGING ONLY. Never point any scenario in this directory at production.
// See load-tests/README.md before running anything here.

import http from "k6/http";

const PRODUCTION_HOST_FRAGMENTS = [
  "greenacreeaglesfc.com",
  "website-4h5.pages.dev"
];

function resolveBaseUrl() {
  const url = __ENV.STAGING_BASE_URL;
  if (!url) {
    throw new Error(
      "STAGING_BASE_URL is required and must point at an isolated staging deployment. " +
        "Example: k6 run -e STAGING_BASE_URL=https://staging.example.pages.dev load-tests/scenarios/public-burst.js"
    );
  }
  const lower = url.toLowerCase();
  if (PRODUCTION_HOST_FRAGMENTS.some((fragment) => lower.includes(fragment))) {
    throw new Error(
      `Refusing to run: "${url}" looks like a production host (${PRODUCTION_HOST_FRAGMENTS.join(", ")}). ` +
        "Load tests must only target an isolated staging Cloudflare Pages deployment and staging Supabase project."
    );
  }
  return url.replace(/\/+$/, "");
}

export const BASE_URL = resolveBaseUrl();

// Optional: a comma-separated allowlist of pre-seeded staging session cookies
// or bearer values for authenticated scenarios (mixed-portal, team-board,
// canteen-rush, wallet-contention). Never populate this with production
// credentials or real member accounts. See README.md "Seed requirements".
export const STAGING_TEST_SESSIONS = (__ENV.STAGING_TEST_SESSIONS || "")
  .split(",")
  .map((value) => value.trim())
  .filter(Boolean);

export const COMMON_HEADERS = {
  "content-type": "application/json",
  // Identify load-test traffic so it can be filtered out of real analytics
  // and so staging-side logging/alerting can distinguish it from organic use.
  "x-load-test": "greenacre-eagles-staging-suite"
};

/**
 * Baseline percentile thresholds shared across scenarios, matching the SLOs
 * documented in docs/production-readiness-audit-20260729.md
 * ("Controlled staging load-test plan"). Individual scenarios may tighten
 * these (e.g. for money-path RPCs) but should not loosen them without an
 * explicit, documented reason.
 */
export const READ_THRESHOLDS = {
  http_req_duration: ["p(50)<600", "p(95)<1500", "p(99)<3000"],
  http_req_failed: ["rate<0.01"]
};

export const WRITE_THRESHOLDS = {
  http_req_duration: ["p(50)<800", "p(95)<2000", "p(99)<4000"],
  http_req_failed: ["rate<0.01"]
};

/**
 * Abort criteria (operator-enforced, not all automatable in k6 thresholds
 * alone -- some require watching Supabase/Cloudflare dashboards live during
 * the run). See README.md "Abort thresholds" for the full checklist.
 */
export const ABORT_THRESHOLDS = Object.freeze({
  unexpectedErrorRatePerMinute: 0.05, // >5% unexpected errors for one minute
  dbCpuPercent: 85, // sustained for two minutes
  dbConnectionsPercent: 85,
  anyDataIntegrityMismatch: true,
  any5xxOnMoneyRpc: true,
  anyWorkerResourceLimitError: true
});

export function jitterSleepSeconds(minSeconds, maxSeconds) {
  return minSeconds + Math.random() * (maxSeconds - minSeconds);
}

/**
 * Cloudflare Turnstile ships documented "always passes" test keys for
 * automated testing (see https://developers.cloudflare.com/turnstile/troubleshooting/testing/ --
 * re-verify current values before relying on them, Cloudflare may change them).
 * Configure the staging environment's TURNSTILE_SECRET_KEY to the matching
 * always-passing test secret so these scenarios can exercise real auth
 * endpoints without solving a real challenge. Never use these values, or
 * disable Turnstile, on production.
 */
export const TURNSTILE_TEST_RESPONSE_TOKEN = __ENV.STAGING_TURNSTILE_TEST_TOKEN || "XXXX.DUMMY.TOKEN.XXXX";

/**
 * Logs a seeded staging test account in via the real /api/auth/signin form
 * endpoint and relies on k6's per-VU cookie jar to retain the resulting
 * Supabase session cookies for subsequent requests made by the same VU.
 *
 * Requires TURNSTILE to be configured with an always-pass test secret in the
 * staging environment (see TURNSTILE_TEST_RESPONSE_TOKEN above).
 */
export function stagingSignIn(email, password) {
  return http.post(
    `${BASE_URL}/api/auth/signin`,
    {
      email,
      password,
      "cf-turnstile-response": TURNSTILE_TEST_RESPONSE_TOKEN
    },
    {
      headers: { origin: BASE_URL },
      redirects: 0,
      tags: { name: "auth_signin" }
    }
  );
}

/** Deterministically maps a k6 virtual user to one of N seeded staging test accounts. */
export function seededTestAccount(vu, poolSize, emailPrefix = "loadtest-user") {
  const index = ((vu - 1) % poolSize) + 1;
  return {
    email: `${emailPrefix}-${index}@${__ENV.STAGING_TEST_EMAIL_DOMAIN || "loadtest.invalid"}`,
    password: __ENV.STAGING_TEST_PASSWORD || "ChangeMe-Staging-Only-1!"
  };
}
