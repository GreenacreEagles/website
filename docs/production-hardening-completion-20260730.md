# Production hardening completion — 2026-07-30

Implementation of the production-readiness audit (`docs/production-readiness-audit-20260729.md`). This is an implementation record, not a second audit.

## Final readiness decision

**Ready for controlled club launch after manual actions below (especially migrations + backups), with 100-user capacity still unproven until staging load tests run.**

Phase 0 and Phase 1 application code is implemented in this working tree. Two forward-only migrations are **created and validated as SQL artifacts but not applied** to the connected Supabase project from this environment (per explicit restriction: no `supabase db push` / reset / repair).

Nothing was committed, pushed, or deployed.

## Manual payment status

| Item | Status |
|---|---|
| `PAYMENT_PROVIDER=manual` | Formalised in `.env.example` and `src/lib/payments.ts` |
| Online payment UI | Not introduced; merchandise/canteen remain pay-at-club |
| External gateway calls | None |
| `PAYMENT_WEBHOOK_SECRET` | **Not required** while manual |
| `/api/webhooks/payments` | Returns safe 503 disabled response in manual mode |
| Pay-at-club checkout | Unchanged and rate-limited |
| Admin manual payment recording | Preserved (canteen/merchandise/wallet settlement) |
| Wallet + voucher methods | Preserved |
| Payment vs fulfilment | Remain separate |
| Audit | Existing order/wallet audit paths retained |

**Missing payment webhook secret finding:** Not applicable while `PAYMENT_PROVIDER=manual` (also mitigated by manual-payment feature gating).

## Finding disposition

### Critical

| ID | Original | Disposition | Evidence / files | Remaining risk | Manual action |
|---|---|---|---|---|---|
| C1 | No production-grade recovery | **Mitigated (ops)** | `docs/backup-and-recovery-runbook.md`, `scripts/backup/*` | Free-plan still has no managed PITR until Pro or scheduled dumps run | Upgrade Supabase to Pro **or** schedule encrypted dumps; enable R2 versioning/second copy; run isolated restore drill |
| C2 | Child provisioning non-atomic | **Resolved (code)** pending migration apply | `child-account.ts`, `complete_child_account_provisioning`, `child_account_provisioning` table, compensation delete/ban, tests | Until migration applied, production still runs old path | Apply `20260730010000_production_hardening_core.sql` |

### High

| ID | Original | Disposition | Evidence | Remaining risk | Manual action |
|---|---|---|---|---|---|
| H1 | Public SSR not edge-cached | **Mitigated** | Homepage `get_homepage_content` (8→1 calls on success); Cache API helpers + `resolveCacheControl`; middleware edge match/store | CF Pages Free may still show DYNAMIC until Cache Rule configured | Add Cloudflare Cache Rule for anonymous GET HTML on public paths |
| H2 | No app rate limiting | **Resolved** | `consume_rate_limit` RPC + memory fallback; auth/posts/likes/checkout/wallet/uploads/invitations/WWCC/reorder | Isolate memory fallback is per-Worker until migration applied | Apply migration; monitor 429s |
| H3 | Unbounded public lists | **Resolved** | `PAGE_BOUNDS` + clamps on events/social/teams/news | — | — |
| H4 | Admin lists capped not pageable | **Mitigated** | Offset pagination on wallets/users/news; tighter bounds on volunteers/event detail | Not every admin list has full cursor UI | Add cursors for remaining large admin tables as data grows |
| H5 | Partial poll / R2 orphans | **Resolved / mitigated** | Atomic `create_team_post_with_poll`; `diagnose_r2_file_orphans` | Orphan cleanup still manual | Schedule diagnostics |
| H6 | Reaction race | **Resolved** | `set_team_post_reaction` RPC | Pending migration apply | Apply migration |
| H7 | Auth/SMTP limits | **Deferred (ops)** | Auth rate limits + Turnstile retained; signup burst suite in k6 | Built-in email limit still blocks 100 signups/hour without custom SMTP | Configure custom SMTP; enable leaked-password protection |
| H8 | Migration history unsafe | **Accepted / out of scope** | No historical migration edits; forward-only only | Drift remains | Keep reconciliation doc; never blind `db push` |

### Medium

| ID | Original | Disposition | Evidence | Remaining risk | Manual action |
|---|---|---|---|---|---|
| M1 | Index alignment | **Resolved (evidence-based)** | Indexes for team_posts feed, wallet ledger, active articles, unread notifications, family_members | Need EXPLAIN at scale after apply | Apply migration; re-check advisors after data growth |
| M2 | Over-indexing / duplicate reaction index | **Deferred** | Not dropped (awaiting migration reconciliation) | Duplicate index storage cost only | Drop duplicate after reconciliation |
| M3 | Multiple permissive policies | **Deferred** | No broad rewrite | Eval cost at scale | Consolidate high-traffic tables later |
| M4 | SECURITY DEFINER surface | **Mitigated** | New functions use `search_path=''`, auth checks, minimal grants | Inventory remains large | Keep release review |
| M5 | Leaked-password protection | **Deferred (dashboard)** | Documented | Weak passwords | Enable in Supabase Auth settings |
| M6 | Observability / alerts | **Mitigated (docs)** | `docs/monitoring-and-alerting-runbook.md` + `src/lib/logging.ts` | Alerts not configured in CF/Supabase dashboards | Configure alerts |
| M7 | Outbox scheduling unclear | **Deferred** | Documented in monitoring runbook | Stuck queue possible | Confirm cron/manual caller |
| M8 | Payment webhook / shared secret | **Not applicable** while manual | Manual gating | If online payments enabled later, need provider signatures | Keep manual until gateway project |
| M9 | File ops / orphans | **Mitigated** | Limits, sanitizeFilename, private upload audit, orphan diagnostics | Concurrent upload memory | Keep limits; run orphan report |
| M10 | Preview incomplete | **Deferred (ops)** | Staging notes in load-test README | Preview ≠ staging | Create staging Supabase/R2 |

### Low

| Item | Disposition |
|---|---|
| Large logo PNG | **Accepted** for this pass (design preserved; optimize later) |
| Hero PNG size | **Accepted** (responsive WebP already exist) |
| Public r2.dev domain | **Deferred** dashboard action |
| CSP unsafe-inline | **Accepted** (Astro inline) |

## Before / after performance evidence

| Route | Before (audit) | After (code) |
|---|---|---|
| `/` Supabase calls | 8 in 3 waves | **1** via `get_homepage_content` when RPC available; fallback path retained |
| Public lists | Unbounded events/social/teams | Hard max via `PAGE_BOUNDS` |
| Portal session | `getUser` + `get_portal_context` (memoized) | Unchanged consolidated loader; mutations warned not to reload lists |
| Edge cache | Headers only; CF DYNAMIC | Headers + Cache API attempt + documented Cache Rule need |
| Abuse endpoints | Turnstile only | Turnstile + per-user/IP rate limits |

Measured production TTFB after deploy is **pending** (not deployed). Load tests **not executed** (no staging).

## Security changes

- Manual payment formalisation; webhook disabled safely
- Child provisioning compensation + audit
- Atomic likes/polls
- Rate limiting across auth and high-risk writes
- Shared validation (`validation.ts`) + body byte ceilings for webhook
- Upload filename sanitisation + private upload audit logging
- Cache never stores portal/admin/auth/cookie responses
- Role-matrix contract tests expanded
- Read-only integrity / wallet / R2 diagnostics RPCs

## Reliability changes

- Idempotent child provisioning key + duplicate username short-circuit
- Checkout/wallet/voucher rate limits on top of existing RPC locks
- Duplicate-submit UI guards on child form and team board
- Backup + monitoring runbooks and backup scripts
- k6 staging suite created (execution pending)

## New migrations

| File | Applied? |
|---|---|
| `supabase/migrations/20260730010000_production_hardening_core.sql` | **No — pending manual application** |
| `supabase/migrations/20260730010001_production_hardening_diagnostics.sql` | **No — pending manual application** |

Validate on a production-schema clone first. Do **not** use `supabase db push` blindly while historical migration drift remains.

## Tests run

| Command | Result |
|---|---|
| `npm run test:hardening` | Pass (36) |
| `npm run test:portal` | Pass (5) |
| `npm run test:admin` | Pass (8) |
| `npm run test:auth` | Pass (12) |
| `npm run test:media` | Pass (8) |
| `npm run test:wwcc` | Pass (4) |
| `npm run typecheck` / `lint` | Pass |
| `npm run build` | Pass |
| `npm audit` | **0 vulnerabilities** |
| `git diff --check` | Pass (CRLF warnings only) |
| `supabase test db` | Not run (would require local DB / migration apply) |
| k6 100-user suite | **Not executed** — staging unavailable; suite marked PENDING |

Pre-existing dependency advisories: **none reported** by `npm audit` at completion.

## Load-test status

Suite present under `load-tests/`. Production hostnames rejected. **Execution status: PENDING** until isolated staging + seed data + SMTP sink exist.

## Manual actions (ordered)

1. Apply forward migrations on a clone, then production (SQL apply / dashboard), recording versions:
   - `20260730010000_production_hardening_core`
   - `20260730010001_production_hardening_diagnostics`
2. Set Cloudflare Pages env `PAYMENT_PROVIDER=manual` (confirm webhook secret not required).
3. Add Cloudflare Cache Rule: cache anonymous GET HTML for `/`, `/news*`, `/events*`, `/teams*`, `/social*`, `/sponsors*` when no cookie; bypass portal/admin/api/auth.
4. Choose backup path: Supabase Pro daily backups **or** scheduled `scripts/backup` dumps to independent encrypted storage; enable R2 versioning/second copy.
5. Configure monitoring alerts per `docs/monitoring-and-alerting-runbook.md`.
6. Supabase dashboard: custom SMTP, leaked-password protection, Auth rate limits.
7. Confirm communication outbox invoker / schedule.
8. Create staging Pages + Supabase + R2; run `load-tests/` and integrity diagnostics.
9. Optional: disable public bucket `r2.dev` if unused; optimize logo assets.

## Deployment sequence

1. Merge/review this working tree (not done here).
2. Apply the two new migrations to production via controlled SQL (not `db push`).
3. Deploy Cloudflare Pages build with `PAYMENT_PROVIDER=manual`.
4. Smoke: homepage, login, family child create (staging first), canteen pay-at-club, merchandise pay-at-club, team like/post, webhook returns 503 manual disabled.
5. Confirm Cache-Control and optionally CF-Cache-Status after Cache Rule.
6. Run integrity diagnostics (read-only).
7. Enable backup job / verify Pro backups.
8. Only then schedule staging k6 and broad member invite.

## Confirmation

- **Not committed**
- **Not pushed**
- **Not deployed**
- **No historical migrations edited**
- **No `supabase db reset` / `db push` / migration repair**
- **No online payment gateway implemented**
- **No destructive production load tests**
