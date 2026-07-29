# Load Tests (k6) — Staging Only

**Execution status: PENDING.** As of this writing there is no isolated staging Cloudflare Pages deployment or staging Supabase project for this club platform. Do not run any scenario in this directory until one exists. This suite is written and reviewed ahead of time so it is ready the moment staging exists, per `docs/production-readiness-audit-20260729.md` ("Controlled staging load-test plan").

## Absolute rule: never target production

Every scenario refuses to start unless `STAGING_BASE_URL` is set, and `load-tests/config.js` actively rejects URLs containing the known production hostnames (`greenacreeaglesfc.com`, `website-4h5.pages.dev`). That check is a safety net, not a substitute for care — always double-check the URL you pass in.

- Never point `STAGING_BASE_URL` at the production Pages domain or custom domain.
- Never point a scenario's Supabase-backed staging deployment at the production Supabase project (`qzqezldtklimtupajvxf` per `docs/administrator-runbook.md`). Use a separate staging Supabase project with its own database, Auth configuration, and R2 buckets.
- Never use real member emails, passwords, wallets, or WWCC documents in a load test. Every account and data point should be clearly a test fixture (see "Seed requirements" below).
- Never reuse production service-role keys, R2 credentials, Turnstile secrets, or webhook secrets for staging load tests.

## What staging needs before this suite can run

1. **A separate Cloudflare Pages (or Worker) deployment** of this repository pointed at a separate Supabase project and separate R2 buckets, per `docs/production-readiness-audit-20260729.md` finding M10 ("Preview environment is incomplete").
2. **A staging Supabase project** with:
   - The same schema as production (apply all `supabase/migrations/` in order).
   - A test SMTP sink for Auth emails (never real email delivery) so `signup-burst.js` doesn't send real emails.
   - Leaked-password protection and other Auth settings matching intended production configuration, so results are representative.
3. **Cloudflare Turnstile configured with an "always passes" test secret** (see `load-tests/config.js` `TURNSTILE_TEST_RESPONSE_TOKEN` and the Cloudflare Turnstile testing documentation — re-verify the exact test key values against current docs before use, and never use them on production).
4. **Seed data**, matching the audit's recommended staging seed:
   - 1,000 users across representative roles (member, parent, child, coach, manager, volunteer, canteen staff, registrar, admin).
   - 100 teams.
   - 10,000 team posts, 50,000 reactions.
   - 20,000 wallet ledger entries, including at least one shared/family wallet with a small known balance for `wallet-contention.js`.
   - 5,000 canteen/merchandise orders.
   - 2,000 vouchers, including at least one with a small known remaining value for the voucher-replay case in `wallet-contention.js`.
   - 2,000 events/registrations.
   - At least one in-stock canteen product for `canteen-rush.js` and `wallet-contention.js`.
   - At least one active team post and poll option for `team-board.js` and `mixed-portal.js` reaction/poll checks.
5. **Seeded, dedicated load-test accounts** with predictable emails/passwords (e.g. `loadtest-user-1@loadtest.invalid` … `loadtest-user-100@loadtest.invalid`), provided via the environment variables each scenario documents at the top of its file (`STAGING_TEST_EMAIL_DOMAIN`, `STAGING_TEST_PASSWORD`). Use an email domain that is obviously non-deliverable/reserved for testing.
6. **[k6](https://k6.io/) installed** on the machine running the tests (there is no npm dependency added for this — k6 is a standalone binary, not a Node package).

## Running a scenario (once staging exists)

```bash
k6 run \
  -e STAGING_BASE_URL=https://staging.example.pages.dev \
  -e STAGING_TEST_EMAIL_DOMAIN=loadtest.invalid \
  -e STAGING_TEST_PASSWORD='replace-with-a-staging-only-password' \
  load-tests/scenarios/public-burst.js
```

On Windows PowerShell:

```powershell
k6 run `
  -e STAGING_BASE_URL=https://staging.example.pages.dev `
  -e STAGING_TEST_EMAIL_DOMAIN=loadtest.invalid `
  -e STAGING_TEST_PASSWORD='replace-with-a-staging-only-password' `
  load-tests/scenarios/public-burst.js
```

Each scenario file documents any additional environment variables it needs (seeded team/product/wallet/voucher IDs, etc.) in its header comment. Run scenarios one at a time initially; only combine them once each passes individually, to make failures easier to attribute.

Write result artifacts (JSON summaries, HTML reports) to `load-test-results/`, which is gitignored — never commit raw load-test output, since it may include response bodies with staging test data.

```bash
k6 run --summary-export=load-test-results/public-burst-summary.json load-tests/scenarios/public-burst.js
```

## Scenarios in this suite

| File | Mirrors audit scenario | Purpose |
|---|---|---|
| `scenarios/public-burst.js` | Scenario 1 (read-heavy) | 100-user ramp across anonymous public pages (`/`, `/news/`, `/teams/`, `/events/`, `/social/`). Validates public-page amplification and caching (audit H1). |
| `scenarios/mixed-portal.js` | Scenario 2 (mixed) | 100 authenticated members: ~70% reads, ~20% posts/reactions, ~5% canteen checkout, ~5% wallet/family actions, held 15 minutes. |
| `scenarios/signup-burst.js` | Scenario 3 (signup) | 20 simultaneous signups, then 100 signups ramped over 5 minutes. Validates Auth/email rate limits (audit H7). |
| `scenarios/team-board.js` | Scenario 4 (team board) | 80 readers, 10 coaches posting (including polls), 40 reaction/poll actions. Validates atomic post+poll creation and reaction race handling (audit H5/H6). |
| `scenarios/canteen-rush.js` | Scenario 5 (canteen rush) | 50 browsing/adding to cart, 20 simultaneous checkouts, 5 staff order-status transitions. Validates checkout locking/idempotency. |
| `scenarios/wallet-contention.js` | Scenario 6 (wallet contention) | 20 concurrent top-ups against a shared wallet, duplicate checkout idempotency-key replay, voucher double-redemption, and a deliberate insufficient-balance attempt. |

## Abort thresholds

Stop the run immediately (`Ctrl+C`, or let k6 threshold-abort where configured) if, at any point:

- Unexpected error rate exceeds **5%** for one minute (excluding intentionally-expected 429s in `signup-burst.js` and intentionally-expected conflict responses in `wallet-contention.js` — those are checked explicitly, not counted as generic failures).
- Any data-integrity mismatch appears when you run `scripts/backup/run-integrity-diagnostics.sql` against the staging project (before, during a paused checkpoint, or after the run).
- Any 5xx response occurs on a money-path RPC endpoint (`wallet-top-up`, `canteen-checkout`, `merchandise-checkout`, `redeem-voucher`, `event-ticket-order`). k6 checks in each scenario already require these to be `303`/`409`/`429`, never `5xx` — a threshold failure here means stop and investigate, don't just re-run.
- Supabase database CPU exceeds **85%** for two minutes (watch the Supabase dashboard live during the run).
- Supabase database connections exceed **85%** of the available pooler limit.
- Any Cloudflare Worker resource-limit error appears (CPU exceeded, memory exceeded, subrequest limit) in Worker logs.

These mirror `docs/production-readiness-audit-20260729.md` ("Controlled staging load-test plan") and `docs/monitoring-and-alerting-runbook.md`.

## After each run (cleanup and reconciliation)

1. Run `scripts/backup/run-integrity-diagnostics.sql` (or `scripts/diagnostics/run-integrity-checks.mjs`) against the staging project. Confirm no new wallet-reconciliation mismatches, no new orphaned records beyond an expected baseline, and no unexpected duplicate-key/voucher-replay side effects.
2. Reconcile ledger totals, voucher remaining values, order/item totals, and stock counts against what the seed data and the scenario's expected write volume predict.
3. Check for orphaned R2 objects (`diagnose_r2_file_orphans`) if any scenario exercised uploads.
4. Delete or reset the load-test-generated rows (accounts created by `signup-burst.js`, orders created by `canteen-rush.js`/`wallet-contention.js`, posts created by `team-board.js`) — or, simpler for a small club, tear down and recreate the entire staging project/buckets from a known-good seed snapshot before the next run, per the audit's recommended cleanup approach.
5. Never copy staging load-test output (including `load-test-results/`) into a location a real member or the public could reach.

## Notes on realism and what to adapt before running

These scripts call the platform's real form-encoded API endpoints (not a mocked API) so results are representative, which means a few things need real values before they will actually pass:

- **Authentication**: scenarios that need a signed-in member sign in via `/api/auth/signin` using seeded test accounts and rely on k6's per-VU cookie jar for the resulting Supabase session cookie. This requires the seeded accounts in "Seed requirements" above to actually exist in staging.
- **Turnstile**: `/api/auth/signin` and `/api/auth/signup` verify a Cloudflare Turnstile token server-side. Configure staging's `TURNSTILE_SECRET_KEY` to a Cloudflare-documented "always passes" test secret so these endpoints can be exercised without solving a real challenge.
- **Seeded entity IDs**: scenarios that act on a specific team, post, poll option, product, wallet, or voucher expect that ID via an environment variable (documented per-scenario) with a placeholder all-zero UUID default. Replace these with real staging IDs — the scripts will otherwise run but every write against them will correctly fail as "not found," which still exercises the endpoint's error path but won't test the intended success path.
- **CSRF/Origin checks**: the app's middleware rejects cross-site state-changing API requests based on `Origin`/`Sec-Fetch-Site`. Each write request in this suite sets `Origin` to `STAGING_BASE_URL` to pass same-origin checks realistically.

## Related documents

- `docs/production-readiness-audit-20260729.md` — origin of every scenario and SLO in this suite.
- `docs/monitoring-and-alerting-runbook.md` — what should be alerting while a load test runs.
- `docs/backup-and-recovery-runbook.md` — restore an isolated project quickly if a load test corrupts staging state beyond easy repair.
- `scripts/backup/run-integrity-diagnostics.sql` / `scripts/diagnostics/run-integrity-checks.mjs` — post-run reconciliation.
