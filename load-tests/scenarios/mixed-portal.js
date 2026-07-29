// Mixed portal scenario: 100 authenticated members mixing reads and writes.
//
// STAGING ONLY -- see ../README.md. Do not run against production.
//
// Mirrors "Scenario 2: Mixed" from docs/production-readiness-audit-20260729.md:
// 100 VUs, roughly 70 readers, 20 posts/reactions, 5 canteen checkouts,
// 5 family/wallet/event actions, held for 15 minutes.
//
// Requires a staging Supabase project seeded with test member accounts
// (see README.md "Seed requirements") and Turnstile configured with an
// always-pass test secret (see ../config.js).
//
// Usage:
//   k6 run \
//     -e STAGING_BASE_URL=https://staging.example.pages.dev \
//     -e STAGING_TEST_EMAIL_DOMAIN=loadtest.invalid \
//     -e STAGING_TEST_PASSWORD='...' \
//     load-tests/scenarios/mixed-portal.js

import http from "k6/http";
import { check, group, sleep } from "k6";
import {
  BASE_URL,
  READ_THRESHOLDS,
  WRITE_THRESHOLDS,
  jitterSleepSeconds,
  seededTestAccount,
  stagingSignIn
} from "../config.js";

const ACCOUNT_POOL_SIZE = 100;

export const options = {
  scenarios: {
    mixed_portal: {
      executor: "constant-vus",
      vus: 100,
      duration: "15m"
    }
  },
  thresholds: {
    ...READ_THRESHOLDS,
    ...WRITE_THRESHOLDS,
    "http_req_duration{name:auth_signin}": ["p(95)<2000"],
    "http_req_duration{name:portal_reads}": ["p(95)<1500"],
    "http_req_duration{name:team_post_reaction}": ["p(95)<1500"],
    "http_req_duration{name:canteen_checkout}": ["p(95)<2500"],
    "http_req_duration{name:wallet_or_family_action}": ["p(95)<2500"]
  }
};

let signedIn = false;

function ensureSignedIn() {
  if (signedIn) return;
  const account = seededTestAccount(__VU, ACCOUNT_POOL_SIZE);
  const res = stagingSignIn(account.email, account.password);
  check(res, {
    "sign-in did not error server-side": (r) => r.status === 303 || r.status === 200
  });
  signedIn = true;
}

function readPortal() {
  const pages = ["/portal/", "/portal/teams/", "/portal/notice-board/", "/portal/canteen/", "/portal/events/"];
  const path = pages[Math.floor(Math.random() * pages.length)];
  const res = http.get(`${BASE_URL}${path}`, { tags: { name: "portal_reads" } });
  check(res, { "portal read ok": (r) => r.status === 200 || r.status === 303 });
}

function reactToTeamPost() {
  // Placeholder team/post IDs -- replace with real seeded staging IDs, or read
  // them from an API response before posting, once staging data exists.
  const teamId = __ENV.STAGING_SEED_TEAM_ID || "00000000-0000-0000-0000-000000000000";
  const postId = __ENV.STAGING_SEED_POST_ID || "00000000-0000-0000-0000-000000000000";
  const res = http.post(
    `${BASE_URL}/api/portal/team-post-reaction`,
    { team_id: teamId, post_id: postId },
    { headers: { origin: BASE_URL }, redirects: 0, tags: { name: "team_post_reaction" } }
  );
  check(res, { "reaction request handled": (r) => [303, 400, 403, 404].includes(r.status) });
}

function canteenCheckout() {
  const requestKey = `loadtest-${__VU}-${__ITER}-${Date.now()}`;
  const res = http.post(
    `${BASE_URL}/api/portal/canteen-checkout`,
    {
      request_key: requestKey,
      wallet_cents: "0",
      voucher_ids: []
    },
    { headers: { origin: BASE_URL }, redirects: 0, tags: { name: "canteen_checkout" } }
  );
  check(res, { "checkout request handled": (r) => [303, 400, 409].includes(r.status) });
}

function walletOrFamilyAction() {
  const res = http.get(`${BASE_URL}/portal/family/`, { tags: { name: "wallet_or_family_action" } });
  check(res, { "family/wallet page reachable": (r) => r.status === 200 || r.status === 303 });
}

export default function () {
  ensureSignedIn();

  const roll = Math.random();
  group("mixed_portal_action", () => {
    if (roll < 0.7) {
      readPortal();
    } else if (roll < 0.9) {
      reactToTeamPost();
    } else if (roll < 0.95) {
      canteenCheckout();
    } else {
      walletOrFamilyAction();
    }
  });

  sleep(jitterSleepSeconds(2, 5));
}
