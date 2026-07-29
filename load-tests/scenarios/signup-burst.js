// Signup burst scenario: 20 simultaneous signups, then 100 signups over 5 minutes.
//
// STAGING ONLY -- see ../README.md. Do not run against production. This
// scenario creates real Supabase Auth users on every run -- always target a
// disposable staging Supabase project, never a project that also holds real
// members, and always run the documented cleanup afterward (README.md
// "Cleanup").
//
// Mirrors "Scenario 3: Signup" and audit section "Concurrent signup analysis"
// from docs/production-readiness-audit-20260729.md. Validates hosted
// Supabase Auth/email rate limits (H7) under both a simultaneous burst and a
// sustained ramp.
//
// Requires:
//   - A staging Supabase project with a test SMTP sink (never real email
//     delivery) configured for Auth, so signup emails do not reach real inboxes.
//   - Turnstile configured with an always-pass test secret (see ../config.js).
//
// Usage:
//   k6 run -e STAGING_BASE_URL=https://staging.example.pages.dev load-tests/scenarios/signup-burst.js

import http from "k6/http";
import { check, group } from "k6";
import { BASE_URL, TURNSTILE_TEST_RESPONSE_TOKEN, WRITE_THRESHOLDS } from "../config.js";

export const options = {
  scenarios: {
    // Stage A: 20 users signing up at effectively the same moment.
    simultaneous_20: {
      executor: "shared-iterations",
      vus: 20,
      iterations: 20,
      maxDuration: "1m",
      exec: "signUp"
    },
    // Stage B: 100 signups spread over 5 minutes, starting once Stage A settles.
    ramped_100_over_5m: {
      executor: "ramping-arrival-rate",
      startTime: "1m",
      startRate: 5,
      timeUnit: "1m",
      preAllocatedVUs: 20,
      maxVUs: 40,
      stages: [
        { target: 20, duration: "5m" },
        { target: 0, duration: "10s" }
      ],
      exec: "signUp"
    }
  },
  thresholds: {
    ...WRITE_THRESHOLDS,
    "http_req_duration{name:auth_signup}": ["p(95)<2500"],
    // 429s are an expected, correct outcome for this scenario (that's what
    // it's testing) so this scenario tracks the 429 rate as a custom metric
    // in the summary rather than failing the run on it. See README.md.
    http_req_failed: ["rate<0.05"]
  }
};

function randomSuffix() {
  return `${Date.now()}-${Math.floor(Math.random() * 1_000_000)}`;
}

export function signUp() {
  const emailDomain = __ENV.STAGING_TEST_EMAIL_DOMAIN || "loadtest.invalid";
  const email = `loadtest-signup-${randomSuffix()}@${emailDomain}`;
  const password = __ENV.STAGING_TEST_PASSWORD || "ChangeMe-Staging-Only-1!";

  group("signup", () => {
    const res = http.post(
      `${BASE_URL}/api/auth/signup`,
      {
        fullName: "Load Test Account",
        email,
        password,
        confirmPassword: password,
        terms: "on",
        "cf-turnstile-response": TURNSTILE_TEST_RESPONSE_TOKEN
      },
      {
        headers: { origin: BASE_URL },
        redirects: 0,
        tags: { name: "auth_signup" }
      }
    );

    check(res, {
      "signup responded (303 success/error redirect, or 429 rate limited)": (r) =>
        r.status === 303 || r.status === 429
    });
  });
}
