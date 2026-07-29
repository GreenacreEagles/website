# Monitoring and Alerting Runbook

This runbook defines what to monitor, what to alert on, safe logging fields, and what must never be logged for the Greenacre Eagles FC platform (Cloudflare Pages/Workers + Supabase Postgres/Auth + R2).

It expands the baseline in `docs/production-readiness-audit-20260729.md` ("Observability and monitoring plan") into concrete thresholds and operating notes. Re-check current Cloudflare and Supabase dashboard capabilities before wiring alerts, since exact metric names and alerting UI change over time.

## 1. Alert catalogue

Each row is a signal to alert on, with a starting threshold suitable for a small club's traffic. Tighten thresholds once real baseline data exists; these are initial, not guaranteed-correct, values.

| # | Signal | Source | Threshold | Severity | Notes |
|---|---|---|---|---|---|
| 1 | Pages/Worker 5xx rate | Cloudflare Pages/Workers analytics or Worker logs | >1% of requests over 5 minutes, or ≥10 errors in 5 minutes | High | Page the technical owner immediately if it correlates with a money route (`/api/portal/*checkout*`, `/api/webhooks/payments`, wallet endpoints). |
| 2 | Worker CPU time exceeded | Cloudflare Worker exception/analytics (`exceededCpu`) | Any occurrence, sustained (≥3 in 15 minutes) | High | Free plan CPU limit is 10ms/request; repeated exceedance usually means an unbounded query or loop, not just load. |
| 3 | Worker memory exceeded / isolate OOM | Cloudflare Worker exception logs | Any occurrence | High | Check concurrent upload handling first — uploads buffer file bytes in Worker memory. |
| 4 | Public route p95 TTFB | Cloudflare Web Analytics / synthetic checks on `/`, `/news/`, `/teams/`, `/events/` | >1.5s sustained over 15 minutes | Medium | Homepage is currently dynamic (`CF-Cache-Status: DYNAMIC`); expect this to be the first to trip until H1 caching is fixed. |
| 5 | Portal route p95 server time | Worker/Pages Function timing for `/portal/*` | >2.0s sustained over 15 minutes | Medium | Compare against `get_portal_context` and per-page Supabase call counts before assuming a database problem. |
| 6 | Supabase database CPU | Supabase dashboard / Postgres stats | >70% sustained for 15 minutes | Medium; High at >90% | Free-plan compute is shared/Nano — sustained CPU pressure is an early signal to consider a compute upgrade. |
| 7 | Supabase database connections | Supabase dashboard (`pg_stat_activity` count vs. pooler limit) | >70% of available warning; >85% critical | High at critical | The app uses PostgREST rather than per-request direct connections, so a spike usually means a leak (long transaction, stuck RPC) rather than normal traffic growth. |
| 8 | Slow queries | `pg_stat_statements` (already installed) — query by `mean_exec_time`/`calls` | Any query >500ms mean, repeated ≥10 times in 10 minutes | Medium | Check `team_posts`, wallet ledger, and canteen order queries first per the audit's M1 index notes. |
| 9 | Deadlocks / long lock waits | Postgres logs (`log_lock_waits`) or Supabase logs | Any deadlock; any lock wait >2 seconds on a checkout/wallet/voucher RPC | High | Wallet and checkout RPCs intentionally take row locks (`for update`); a wait itself is not automatically a bug, but a deadlock or a wait over 2s is. |
| 10 | Supabase Auth 429 responses | Supabase Auth logs / application-side capture of Auth error codes | >5% of Auth calls return 429 over any 15-minute window, or any 429 during a known signup burst (e.g. registration day) | High during a launch/signup event; Medium otherwise | Free-tier hosted email sending is limited to a small number of project-wide emails per hour unless custom SMTP is configured — verify SMTP status before assuming this is abuse. |
| 11 | Communication outbox backlog | `communication_outbox` table (oldest pending row age, failed-attempt count) | Oldest pending item >10 minutes old, or any item with `failed_attempts >= 3` | Medium; High if backlog exceeds 50 items | No Cloudflare Cron trigger was found in the last audit — confirm who/what dispatches the outbox before assuming this alert will ever fire under normal operation. |
| 12 | R2 operation failures | Application-side capture of R2 `put`/`get`/`delete` error responses in Worker logs | >3 failures in 5 minutes on either bucket | High if on the private/WWCC bucket; Medium on public media | Distinguish "object not found" (may indicate orphan/reconciliation issue, see #14) from transport/auth failures (may indicate credential/binding misconfiguration). |
| 13 | Wallet reconciliation mismatch | `diagnose_wallet_reconciliation()` RPC, run on a schedule | Any nonzero mismatch between derived balance and ledger sum | High — treat as a money-integrity incident, not a background task failure | Never auto-correct; investigate the specific wallet's ledger history before any manual adjustment. |
| 14 | R2/file-record orphans | `diagnose_r2_file_orphans()` RPC, run on a schedule | Any new orphan since the last run | Medium; High if it affects an active WWCC submission | A rising trend suggests the upload/metadata-write path is failing partway (see audit H5/M9). |
| 15 | Data integrity findings | `diagnose_data_integrity()` RPC, run on a schedule | Any new finding since the last run (auth users without profile, duplicate wallets, duplicate active roles, invalid order-status combinations, etc.) | Medium; High for duplicate wallets or auth users without a profile | Compare counts run-over-run rather than alerting on the raw non-zero baseline if a known issue already exists — track it as a tickable backlog item instead. |
| 16 | Privileged/audit events | `audit_logs` table | Alert (not just log) on: super-admin role grant, wallet manual debit/credit, WWCC approval/rejection, role elevation, child account provisioning failure | Informational for routine review; High if it happens outside expected admin activity (e.g. outside business hours with no corresponding admin session) | Route a daily digest to the technical owner and a weekly summary to the president/secretary; this is as much a governance control as an operational one. |
| 17 | Duplicate webhook / voucher replay attempts | Payment webhook `(provider, provider_event_id)` unique-constraint violations; voucher redemption unique-constraint violations | Any unusual rise above baseline | Medium | Currently low-risk in practice because `PAYMENT_PROVIDER=manual` (see §4), but voucher replay applies regardless of payment provider. |

## 2. Safe structured logging fields

All application logs should be structured JSON with a bounded, allow-listed field set. `src/lib/logging.ts` already implements this pattern (`logInfo`/`logWarn`/`logError` plus a `SENSITIVE_KEY` scrub and a 500-character value truncation) — extend that module rather than introducing a second logging convention.

Approved fields:

| Field | Purpose |
|---|---|
| `requestId` | Correlates all log lines for one request/RPC chain (`crypto.randomUUID()` per request). |
| `route` | The matched route/endpoint, e.g. `/api/portal/canteen/checkout`. |
| `operation` | A stable operation name, e.g. `wallet.debit`, `wwcc.review`, `child.provision`. |
| `durationMs` | Wall-clock time for the operation. |
| `status` | HTTP status code or RPC-level outcome status. |
| `errorCode` | A stable, non-sensitive error identifier (exception name, RPC error code) — never the raw exception message if it might embed user-supplied content. |
| `actorId` | The authenticated user's UUID (`auth.uid()` / `profiles.id`) — the UUID only, never email, name, or username. |
| `entityId` / `entityType` | The UUID and type of the record acted on (wallet ID, order ID, post ID) — UUID only. |
| `callCount` | Number of downstream Supabase/R2 calls in the request, useful for amplification tracking (see audit H1). |
| `rateLimited` | Boolean flag when a request was rejected by rate limiting. |

Never add a new field to a log call without checking it against §3 first.

## 3. Data that must never be logged

Enforce this at the logging layer, not just by convention — `src/lib/logging.ts`'s `SENSITIVE_KEY` pattern already strips any field whose *name* matches `password|token|secret|authorization|cookie|api[_-]?key|wwcc|card|cvv|payment[_-]?payload|turnstile`. That protects against accidental field names, but does not protect against secrets embedded in a *value* under an innocuous field name (e.g. a full exception message that happens to contain a service-role key from a misconfigured client). When adding new logging:

- **Never log:** passwords, session/auth tokens, Supabase service-role keys, R2 access/secret keys, Turnstile tokens/secrets, `PAYMENT_WEBHOOK_SECRET`/`COMMUNICATION_WORKER_SECRET`, full cookie headers, raw JWTs.
- **Never log:** WWCC numbers, WWCC document contents, or any field explicitly named `wwcc*`.
- **Never log:** full payment payloads (card numbers, payer details) — even though the current provider is manual/at-club-only, keep this rule in place for when/if an online gateway is ever enabled.
- **Never log:** full member PII in bulk — names, emails, phone numbers, home addresses. Use `actorId`/`entityId` UUIDs instead; look up human-readable details on demand from the admin UI, which already enforces RLS/permission checks, rather than duplicating that data into logs.
- **Never log:** raw exception messages or stack traces that might contain interpolated user input, request bodies, or connection strings — log `error.name` (already the pattern in `withRequestLog`) or a curated `errorCode`, not `error.message`, unless the message has been reviewed as safe.
- **Truncate defensively:** even approved string fields should be length-capped (the existing 500-character truncation in `scrub()` is a reasonable default) so a large payload can't be exfiltrated through a log field.

If a new diagnostic genuinely requires more detail than the safe fields allow (e.g. debugging a specific incident), pull it live from the database with a scoped, audited, read-only query — do not widen the standing log schema to capture it by default.

## 4. Payment provider note

The application currently runs with `PAYMENT_PROVIDER=manual` (`src/lib/payments.ts`) because **the club accepts payment at the club only**. As a result:

- There is no live payment gateway webhook to sign/verify. `PAYMENT_WEBHOOK_SECRET`-related alerts (webhook signature failures, webhook secret misconfiguration) are **not applicable** while the provider remains `manual` — the webhook endpoint fails closed with a 503 by design in this mode.
- Do not build or enable payment-webhook-specific alerting until `PAYMENT_PROVIDER` is switched to a real gateway (`stripe`, `square`, etc.). At that point, revisit this runbook and add: webhook signature verification failure rate, webhook secret age reminder, and duplicate `(provider, provider_event_id)` rate — this is future scope, not part of the current alert catalogue in §1.
- Wallet, voucher, and canteen/merchandise reconciliation alerts (§1 rows 13, 17) remain fully applicable regardless of payment provider, because those systems operate independently of the (currently disabled) online payment path.

## 5. Where alerts should go

- **Technical owner:** all alerts, all severities.
- **President or secretary:** high-severity alerts involving money integrity (wallet reconciliation mismatch, privileged wallet/role audit events), data-loss risk, or any restore/incident under `docs/backup-and-recovery-runbook.md`.
- **Privacy officer / compliance lead:** any alert touching WWCC data specifically (orphaned WWCC file, WWCC review audit events).

Keep the notification channel simple for a small club — a shared, access-controlled channel (email distribution list or a private chat channel) is sufficient; avoid standing up paging infrastructure disproportionate to club scale.

## 6. Implementation notes (current platform capability)

- **Cloudflare:** enable Web Analytics if acceptable for privacy, and configure Cloudflare notifications for Pages/Workers error rate and CPU/exceeded-limit events from the Cloudflare dashboard (Notifications → create). Re-check current Cloudflare notification types before wiring, since the product surface changes.
- **Supabase:** use the dashboard's built-in usage/health graphs for CPU, connections, and egress as a first pass. `pg_stat_statements` is already installed and can be queried directly for slow-query tracking (see audit query examples). Supabase may also offer log-drain/webhook integrations — check current documentation for what's available on the active plan before assuming a feature exists.
- **Application-level diagnostics:** the `diagnose_data_integrity`, `diagnose_wallet_reconciliation`, and `diagnose_r2_file_orphans` database functions (added in `supabase/migrations/20260730010001_production_hardening_diagnostics.sql`) are read-only, permission-checked (`users.manage` / `wallet.adjust`), and safe to run on a schedule. `scripts/diagnostics/run-integrity-checks.mjs` documents how to invoke them from a scheduled job using a service-role key, printing only summary counts by default (see that script for the no-PII-by-default behavior).
- **Audit trail:** `audit_logs` already captures privileged actions (role grants, wallet adjustments, WWCC review, child provisioning). Treat it as the source of truth for row 16 above rather than re-deriving privileged-action alerts from application logs.

## 7. Retention

- Cloudflare-included logs: retain as long as the current plan provides by default; do not pay for extended retention unless a specific incident requires it.
- Security/audit events (`audit_logs` table): retain at least 12 months. Export a periodic snapshot to the same independent, encrypted storage used for database backups (`docs/backup-and-recovery-runbook.md` §7) rather than relying solely on the live table.
- Routine application logs: 30 days is a reasonable default if the platform used allows configuring this; longer retention has limited value for a club of this size and adds cost.

## 8. Related documents

- `docs/production-readiness-audit-20260729.md` — original findings this runbook operationalizes (see "Observability and monitoring plan" and finding M6).
- `docs/backup-and-recovery-runbook.md` — what to do once an alert indicates data loss or requires a restore.
- `src/lib/logging.ts` — the actual safe-logging implementation this runbook describes.
- `src/lib/payments.ts` — `PAYMENT_PROVIDER` mode used by §4.
