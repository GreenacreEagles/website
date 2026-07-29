// Public burst scenario: 100 anonymous users ramping onto public pages.
//
// STAGING ONLY -- see ../README.md. Do not run against production.
//
// Mirrors "Scenario 1: Read-heavy" from
// docs/production-readiness-audit-20260729.md: ramp 0->100 over 2 minutes,
// hold 10 minutes, hitting homepage/news/teams/events/social.
//
// Usage:
//   k6 run -e STAGING_BASE_URL=https://staging.example.pages.dev load-tests/scenarios/public-burst.js

import http from "k6/http";
import { check, group, sleep } from "k6";
import { BASE_URL, COMMON_HEADERS, READ_THRESHOLDS, jitterSleepSeconds } from "../config.js";

export const options = {
  scenarios: {
    public_burst: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: "2m", target: 100 },
        { duration: "10m", target: 100 },
        { duration: "1m", target: 0 }
      ],
      gracefulRampDown: "30s"
    }
  },
  thresholds: {
    ...READ_THRESHOLDS,
    // Homepage specifically is currently uncached SSR per the audit (H1) --
    // track it separately so a slow homepage doesn't hide in the aggregate.
    "http_req_duration{page:home}": ["p(95)<1500"],
    "http_req_duration{page:news}": ["p(95)<1200"],
    "http_req_duration{page:teams}": ["p(95)<1200"],
    "http_req_duration{page:events}": ["p(95)<1200"],
    "http_req_duration{page:social}": ["p(95)<1200"]
  }
};

const PAGES = [
  { path: "/", tag: "home", weight: 5 },
  { path: "/news/", tag: "news", weight: 3 },
  { path: "/teams/", tag: "teams", weight: 3 },
  { path: "/events/", tag: "events", weight: 2 },
  { path: "/social/", tag: "social", weight: 2 },
  { path: "/sponsors/", tag: "sponsors", weight: 1 }
];

const WEIGHTED_PAGES = PAGES.flatMap((page) => Array(page.weight).fill(page));

export default function () {
  const page = WEIGHTED_PAGES[Math.floor(Math.random() * WEIGHTED_PAGES.length)];

  group(`public:${page.tag}`, () => {
    const res = http.get(`${BASE_URL}${page.path}`, {
      headers: COMMON_HEADERS,
      tags: { page: page.tag }
    });

    check(res, {
      "status is 200": (r) => r.status === 200,
      "no set-cookie on public page": (r) => !r.headers["Set-Cookie"],
      "has html body": (r) => typeof r.body === "string" && r.body.length > 0
    });
  });

  sleep(jitterSleepSeconds(1, 3));
}
