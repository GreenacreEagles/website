// Canteen rush scenario: 50 browsing, 20 simultaneous checkouts, 5 staff
// status transitions.
//
// STAGING ONLY -- see ../README.md. Do not run against production. This
// scenario creates real canteen orders/ledger entries in whatever project it
// targets -- always a disposable staging Supabase project.
//
// Mirrors "Scenario 5: Canteen rush" from
// docs/production-readiness-audit-20260729.md. Exercises
// checkout_canteen_cart (cart/product/voucher/wallet locks, order
// idempotency) and update_canteen_order_state under concurrency.
//
// Requires seeded staging canteen product(s) in stock, seeded member/staff
// accounts, and staff accounts holding canteen.orders.fulfil or
// canteen.orders.manage. See README.md "Seed requirements".
//
// Usage:
//   k6 run \
//     -e STAGING_BASE_URL=https://staging.example.pages.dev \
//     -e STAGING_SEED_PRODUCT_ID=<uuid> \
//     -e STAGING_SEED_ORDER_ID=<uuid> \
//     load-tests/scenarios/canteen-rush.js

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

const PRODUCT_ID = __ENV.STAGING_SEED_PRODUCT_ID || "00000000-0000-0000-0000-000000000000";

export const options = {
  scenarios: {
    browsers: {
      executor: "constant-vus",
      vus: 50,
      duration: "8m",
      exec: "browseCanteen"
    },
    simultaneous_checkout: {
      executor: "shared-iterations",
      vus: 20,
      iterations: 20,
      maxDuration: "2m",
      startTime: "1m",
      exec: "checkout"
    },
    staff_transitions: {
      executor: "constant-vus",
      vus: 5,
      duration: "8m",
      exec: "staffTransition"
    }
  },
  thresholds: {
    ...READ_THRESHOLDS,
    ...WRITE_THRESHOLDS,
    "http_req_duration{name:canteen_browse}": ["p(95)<1200"],
    "http_req_duration{name:canteen_add_to_cart}": ["p(95)<1500"],
    "http_req_duration{name:canteen_checkout}": ["p(95)<2500"],
    "http_req_duration{name:canteen_staff_status}": ["p(95)<1500"],
    // Duplicate order-number / idempotency violations must never occur; any
    // failed check here should abort the run per README.md "Abort thresholds".
    checks: ["rate>0.99"]
  }
};

let signedIn = false;
function ensureSignedIn(poolSize, prefix) {
  if (signedIn) return;
  const account = seededTestAccount(__VU, poolSize, prefix);
  stagingSignIn(account.email, account.password);
  signedIn = true;
}

export function browseCanteen() {
  ensureSignedIn(50, "loadtest-browser");
  const res = http.get(`${BASE_URL}/portal/canteen/shop/`, { tags: { name: "canteen_browse" } });
  check(res, { "canteen shop reachable": (r) => r.status === 200 || r.status === 303 });

  const addRes = http.post(
    `${BASE_URL}/api/portal/canteen-cart`,
    { action: "add", product_id: PRODUCT_ID, quantity: "1", return_to: "/portal/canteen/shop/cart/" },
    { headers: { origin: BASE_URL }, redirects: 0, tags: { name: "canteen_add_to_cart" } }
  );
  check(addRes, { "add-to-cart handled": (r) => [303].includes(r.status) });

  sleep(jitterSleepSeconds(3, 8));
}

export function checkout() {
  ensureSignedIn(20, "loadtest-checkout");

  group("canteen_checkout_flow", () => {
    http.post(
      `${BASE_URL}/api/portal/canteen-cart`,
      { action: "set", product_id: PRODUCT_ID, quantity: "2", return_to: "/portal/canteen/shop/cart/" },
      { headers: { origin: BASE_URL }, redirects: 0, tags: { name: "canteen_add_to_cart" } }
    );

    const requestKey = `loadtest-checkout-${__VU}-${Date.now()}`;
    const res = http.post(
      `${BASE_URL}/api/portal/canteen-checkout`,
      {
        request_key: requestKey,
        wallet_cents: "0",
        voucher_ids: []
      },
      { headers: { origin: BASE_URL }, redirects: 0, tags: { name: "canteen_checkout" } }
    );

    check(res, {
      // 303 = accepted (success or a handled validation error rendered as a
      // friendly redirect); 409 would indicate an idempotency/stock conflict,
      // which is an expected possible outcome under simultaneous checkout and
      // should be reviewed, not treated as a hard failure of the script itself.
      "checkout request handled": (r) => [303, 409].includes(r.status)
    });
  });
}

export function staffTransition() {
  ensureSignedIn(5, "loadtest-canteen-staff");
  const orderId = __ENV.STAGING_SEED_ORDER_ID || "00000000-0000-0000-0000-000000000000";
  const statuses = ["accepted", "preparing", "ready_for_pickup", "collected"];
  const status = statuses[Math.floor(Math.random() * statuses.length)];

  const res = http.post(
    `${BASE_URL}/api/admin/canteen-order-status`,
    { order_id: orderId, order_status: status, return_to: "/admin/canteen/" },
    { headers: { origin: BASE_URL }, redirects: 0, tags: { name: "canteen_staff_status" } }
  );
  check(res, { "status transition handled": (r) => [303].includes(r.status) });

  sleep(jitterSleepSeconds(5, 12));
}
