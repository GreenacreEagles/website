// Wallet contention scenario: 20 concurrent attempts against shared and
// individual wallets, duplicate idempotency-key replay, voucher double-
// redemption, and an insufficient-balance attempt.
//
// STAGING ONLY -- see ../README.md. Do not run against production. This
// scenario deliberately tries to trigger conflicts (duplicate keys, replayed
// vouchers, overdrawn wallets) -- only ever run it against a disposable
// staging Supabase project.
//
// Mirrors "Scenario 6: Wallet contention" from
// docs/production-readiness-audit-20260729.md, plus the specific replay and
// insufficient-balance cases called out for this suite. Exercises
// create_wallet_top_up, checkout_canteen_cart, and redeem_voucher under
// concurrency and repeated/duplicate input.
//
// IMPORTANT: this scenario can only validate HTTP-level behaviour (status
// codes, that requests are handled rather than crashing). Whether wallet
// balances, ledger entries, and voucher redemption counts stayed correct
// under contention must be confirmed *after* the run by running
// scripts/backup/run-integrity-diagnostics.sql (specifically
// diagnose_wallet_reconciliation) against the same staging project, per
// README.md "Cleanup" / "After each run".
//
// Requires:
//   - A seeded staging shared/family wallet ID with a known, small balance
//     (STAGING_SEED_WALLET_ID).
//   - A seeded staging voucher redemption code (STAGING_SEED_VOUCHER_CODE)
//     with a known remaining value, and a staff account with
//     canteen.vouchers.redeem permission.
//   - A seeded staging canteen product ID (STAGING_SEED_PRODUCT_ID).
//
// Usage:
//   k6 run \
//     -e STAGING_BASE_URL=https://staging.example.pages.dev \
//     -e STAGING_SEED_WALLET_ID=<uuid> \
//     -e STAGING_SEED_VOUCHER_CODE=<code> \
//     -e STAGING_SEED_PRODUCT_ID=<uuid> \
//     load-tests/scenarios/wallet-contention.js

import http from "k6/http";
import { check, group, sleep } from "k6";
import {
  BASE_URL,
  WRITE_THRESHOLDS,
  jitterSleepSeconds,
  seededTestAccount,
  stagingSignIn
} from "../config.js";

const WALLET_ID = __ENV.STAGING_SEED_WALLET_ID || "00000000-0000-0000-0000-000000000000";
const PRODUCT_ID = __ENV.STAGING_SEED_PRODUCT_ID || "00000000-0000-0000-0000-000000000000";
const VOUCHER_CODE = __ENV.STAGING_SEED_VOUCHER_CODE || "GEVOUCHER:LOADTEST0001";

// A fixed request key shared across VUs in the duplicate-key group so the
// replay is a genuine duplicate, not a per-VU-unique key.
const SHARED_IDEMPOTENCY_KEY = `loadtest-shared-key-${__ENV.STAGING_RUN_ID || "manual-run"}`;

export const options = {
  scenarios: {
    // 20 concurrent top-ups against the same shared wallet.
    shared_wallet_top_up: {
      executor: "shared-iterations",
      vus: 20,
      iterations: 20,
      maxDuration: "1m",
      exec: "topUpSharedWallet"
    },
    // Duplicate idempotency-key checkout replay (should not double-charge).
    duplicate_checkout_key: {
      executor: "shared-iterations",
      vus: 10,
      iterations: 10,
      maxDuration: "1m",
      startTime: "1m",
      exec: "replayCheckoutKey"
    },
    // Voucher double-redemption attempt (same code, concurrent claims).
    voucher_replay: {
      executor: "shared-iterations",
      vus: 5,
      iterations: 5,
      maxDuration: "1m",
      startTime: "2m",
      exec: "replayVoucher"
    },
    // A single deliberate insufficient-balance attempt per iteration.
    insufficient_balance: {
      executor: "shared-iterations",
      vus: 5,
      iterations: 5,
      maxDuration: "1m",
      startTime: "3m",
      exec: "attemptInsufficientBalance"
    }
  },
  thresholds: {
    ...WRITE_THRESHOLDS,
    // The application must reject these conflicts cleanly (redirect with an
    // error message), not 5xx. A 5xx on any money RPC is an abort condition
    // per README.md "Abort thresholds" and docs/monitoring-and-alerting-runbook.md.
    http_req_failed: ["rate<0.01"]
  }
};

let signedIn = false;
function ensureSignedIn(poolSize, prefix) {
  if (signedIn) return;
  const account = seededTestAccount(__VU, poolSize, prefix);
  stagingSignIn(account.email, account.password);
  signedIn = true;
}

export function topUpSharedWallet() {
  ensureSignedIn(20, "loadtest-wallet-owner");
  group("shared_wallet_top_up", () => {
    const res = http.post(
      `${BASE_URL}/api/portal/wallet-top-up`,
      { wallet_id: WALLET_ID, amount: "5.00", provider: "manual", return_to: "/portal/vouchers/" },
      { headers: { origin: BASE_URL }, redirects: 0, tags: { name: "wallet_top_up" } }
    );
    check(res, { "top-up request handled": (r) => r.status === 303 });
  });
  sleep(jitterSleepSeconds(0.5, 2));
}

export function replayCheckoutKey() {
  ensureSignedIn(10, "loadtest-checkout-replay");
  group("duplicate_checkout_key", () => {
    // Add an item first so the cart is non-empty for both attempts.
    http.post(
      `${BASE_URL}/api/portal/canteen-cart`,
      { action: "set", product_id: PRODUCT_ID, quantity: "1", return_to: "/portal/canteen/shop/cart/" },
      { headers: { origin: BASE_URL }, redirects: 0, tags: { name: "canteen_add_to_cart" } }
    );

    const first = http.post(
      `${BASE_URL}/api/portal/canteen-checkout`,
      { request_key: SHARED_IDEMPOTENCY_KEY, wallet_cents: "0", voucher_ids: [] },
      { headers: { origin: BASE_URL }, redirects: 0, tags: { name: "checkout_first_attempt" } }
    );
    const replay = http.post(
      `${BASE_URL}/api/portal/canteen-checkout`,
      { request_key: SHARED_IDEMPOTENCY_KEY, wallet_cents: "0", voucher_ids: [] },
      { headers: { origin: BASE_URL }, redirects: 0, tags: { name: "checkout_replay_attempt" } }
    );

    check(first, { "first checkout handled": (r) => r.status === 303 });
    check(replay, { "replayed checkout key handled without 5xx": (r) => r.status === 303 });
  });
  sleep(jitterSleepSeconds(0.5, 2));
}

export function replayVoucher() {
  ensureSignedIn(5, "loadtest-canteen-staff");
  group("voucher_replay", () => {
    const attempt1 = http.post(
      `${BASE_URL}/api/admin/redeem-voucher`,
      { redemption_code: VOUCHER_CODE, amount: "1.00", device_label: "load-test", return_to: "/portal/canteen/" },
      { headers: { origin: BASE_URL }, redirects: 0, tags: { name: "voucher_redeem_first" } }
    );
    const attempt2 = http.post(
      `${BASE_URL}/api/admin/redeem-voucher`,
      { redemption_code: VOUCHER_CODE, amount: "1.00", device_label: "load-test", return_to: "/portal/canteen/" },
      { headers: { origin: BASE_URL }, redirects: 0, tags: { name: "voucher_redeem_replay" } }
    );

    check(attempt1, { "first voucher redemption handled": (r) => r.status === 303 });
    // The second (replayed) redemption is *expected* to be rejected by the
    // database once the voucher's remaining value is exhausted or the same
    // redemption is otherwise disallowed -- it must still come back as a
    // clean redirect, not a 5xx.
    check(attempt2, { "replayed voucher redemption rejected cleanly": (r) => r.status === 303 });
  });
  sleep(jitterSleepSeconds(0.5, 2));
}

export function attemptInsufficientBalance() {
  ensureSignedIn(5, "loadtest-poor-wallet");
  group("insufficient_balance", () => {
    http.post(
      `${BASE_URL}/api/portal/canteen-cart`,
      { action: "set", product_id: PRODUCT_ID, quantity: "1", return_to: "/portal/canteen/shop/cart/" },
      { headers: { origin: BASE_URL }, redirects: 0, tags: { name: "canteen_add_to_cart" } }
    );

    // Deliberately request far more wallet credit than any seeded staging
    // test wallet should hold, to exercise the insufficient-balance path.
    const res = http.post(
      `${BASE_URL}/api/portal/canteen-checkout`,
      { request_key: `loadtest-insufficient-${__VU}-${Date.now()}`, wallet_cents: "999999", voucher_ids: [] },
      { headers: { origin: BASE_URL }, redirects: 0, tags: { name: "checkout_insufficient_balance" } }
    );

    check(res, {
      "insufficient-balance checkout rejected cleanly (no 5xx)": (r) => r.status === 303
    });
  });
  sleep(jitterSleepSeconds(0.5, 2));
}
