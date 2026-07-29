// Team board scenario: 80 readers, 10 coaches posting, 40 reaction/poll actions.
//
// STAGING ONLY -- see ../README.md. Do not run against production.
//
// Mirrors "Scenario 4: Team board" from docs/production-readiness-audit-20260729.md.
// Exercises create_team_post_with_poll and set_team_post_reaction under
// concurrency (audit findings H5 partial-poll risk and H6 reaction race).
//
// Requires seeded staging team(s), coach account(s) able to post to those
// teams, and general member accounts able to read/react. See README.md
// "Seed requirements".
//
// Usage:
//   k6 run \
//     -e STAGING_BASE_URL=https://staging.example.pages.dev \
//     -e STAGING_SEED_TEAM_ID=<uuid> \
//     load-tests/scenarios/team-board.js

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

const READER_ACCOUNT_POOL = 80;
const COACH_ACCOUNT_POOL = 10;
const TEAM_ID = __ENV.STAGING_SEED_TEAM_ID || "00000000-0000-0000-0000-000000000000";

export const options = {
  scenarios: {
    readers: {
      executor: "constant-vus",
      vus: 80,
      duration: "10m",
      exec: "readTeamBoard"
    },
    coaches_posting: {
      executor: "constant-vus",
      vus: 10,
      duration: "10m",
      exec: "coachPost"
    },
    reactions_and_polls: {
      executor: "constant-vus",
      vus: 40,
      duration: "10m",
      exec: "reactOrVote"
    }
  },
  thresholds: {
    ...READ_THRESHOLDS,
    ...WRITE_THRESHOLDS,
    "http_req_duration{name:team_board_read}": ["p(95)<1200"],
    "http_req_duration{name:team_post_create}": ["p(95)<2000"],
    "http_req_duration{name:team_post_reaction}": ["p(95)<1500"],
    "http_req_duration{name:team_poll_response}": ["p(95)<1500"]
  }
};

let signedIn = false;
function ensureSignedIn(poolSize, prefix) {
  if (signedIn) return;
  const account = seededTestAccount(__VU, poolSize, prefix);
  stagingSignIn(account.email, account.password);
  signedIn = true;
}

export function readTeamBoard() {
  ensureSignedIn(READER_ACCOUNT_POOL, "loadtest-member");
  const res = http.get(`${BASE_URL}/portal/teams/${TEAM_ID}/?tab=posts`, { tags: { name: "team_board_read" } });
  check(res, { "team board reachable": (r) => r.status === 200 || r.status === 303 });
  sleep(jitterSleepSeconds(2, 5));
}

export function coachPost() {
  ensureSignedIn(COACH_ACCOUNT_POOL, "loadtest-coach");
  group("coach_post", () => {
    const isPoll = Math.random() < 0.3;
    const res = http.post(
      `${BASE_URL}/api/portal/team-post`,
      {
        team_id: TEAM_ID,
        title: `Load test update ${Date.now()}`,
        body: "Automated staging load-test post. Safe to delete.",
        post_type: isPoll ? "poll" : "announcement",
        is_pinned: "false"
      },
      { headers: { origin: BASE_URL }, redirects: 0, tags: { name: "team_post_create" } }
    );
    check(res, { "post request handled": (r) => [303].includes(r.status) });
  });
  sleep(jitterSleepSeconds(20, 45));
}

export function reactOrVote() {
  ensureSignedIn(40, "loadtest-reactor");
  // Placeholder IDs -- replace with real seeded staging post/option IDs, or
  // fetch a live post ID from the team board response before acting, once
  // staging data/seeding is finalised.
  const postId = __ENV.STAGING_SEED_POST_ID || "00000000-0000-0000-0000-000000000000";
  const optionId = __ENV.STAGING_SEED_POLL_OPTION_ID || "00000000-0000-0000-0000-000000000000";

  if (Math.random() < 0.7) {
    const res = http.post(
      `${BASE_URL}/api/portal/team-post-reaction`,
      { team_id: TEAM_ID, post_id: postId },
      { headers: { origin: BASE_URL }, redirects: 0, tags: { name: "team_post_reaction" } }
    );
    check(res, { "reaction handled": (r) => [303, 400, 403, 404].includes(r.status) });
  } else {
    const res = http.post(
      `${BASE_URL}/api/portal/team-poll-response`,
      { team_id: TEAM_ID, post_id: postId, option_id: optionId },
      { headers: { origin: BASE_URL }, redirects: 0, tags: { name: "team_poll_response" } }
    );
    check(res, { "poll response handled": (r) => [303, 400, 403, 404].includes(r.status) });
  }
  sleep(jitterSleepSeconds(1, 4));
}
