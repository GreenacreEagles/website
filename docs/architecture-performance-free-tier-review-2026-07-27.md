# Greenacre Eagles FC architecture, performance and free-tier review

**Review date:** 27 July 2026  
**Scope:** repository, current Cloudflare Pages deployment, connected production Supabase project, production logs and schema, and unauthenticated live-route measurements  
**Change policy:** review only. No application optimisation, production migration, permission change, or hosting migration was performed.

## Evidence and limits

This report distinguishes three kinds of evidence:

- **Confirmed:** observed directly in source, deployed configuration, production schema, production logs, platform API responses, or a live request.
- **Code-derived:** counted from the code path. This is reliable for the current revision but is not a distributed trace.
- **Unavailable:** the required metric or authenticated session was not exposed. It is not silently estimated.

The repository was clean before this report was added. No temporary instrumentation was added because the incident could be established from existing production API logs and the current code. There was no authenticated browser session or test credential, so protected-route latency and mutations were not replayed against production. Cloudflare Pages request, CPU, and error telemetry returned no usable series through the connected API. Those metrics are therefore marked unavailable.

## 1. Executive summary

The portal feels slow because every protected page and action first builds an extremely expensive request context. `src/lib/auth/session.ts` verifies the user, reads the profile and role assignments, then makes one Supabase RPC request for every known permission. There are 56 permission keys in the combined navigation lists, followed by a separate wildcard check. With unread-notification and managed-child queries, the shared context costs approximately **62 outbound Supabase HTTP requests before the page or action does its own work**.

This is also the exact cause of the Cloudflare error while creating a merchandise product. The product operation itself is one normal `merchandise_products` insert. It does not create variants, stock rows, images, or per-field audit records in a loop. The action nevertheless starts with the 62-call shared context and then performs its insert, for approximately **63 external subrequests**. Cloudflare Workers Free permits 50 external subrequests per invocation, so the request is structurally incapable of succeeding reliably. The redirect after creation is a new browser request, not a subrequest inside the failing invocation.

Production evidence corroborates this:

- Supabase API logs show `/auth/v1/user`, a profile read, a role-assignment read, and then dozens of `/rest/v1/rpc/has_permission` calls in one cluster.
- `pg_stat_statements` records **11,464 `has_permission` calls**, with a mean database execution time of about **0.995 ms**. The SQL is inexpensive; issuing it thousands of times across HTTP is not.
- One recent log cluster spans about 1.4 seconds from the auth lookup to the end of permission fan-out. This is not a controlled end-to-end latency measurement, but it demonstrates the repeated provider-boundary work.

The primary problem is therefore **application request architecture**, not a fundamentally slow Supabase database and not an unsuitable Cloudflare platform. Cloudflare exposes the flaw earlier because its free plan has a clear per-invocation subrequest limit. Moving the unchanged code to Vercel would remove that particular ceiling but retain the 57 permission round trips, the latency, Supabase egress, and the poor scaling curve.

**Recommendation:** stay on Cloudflare. Replace per-permission HTTP fan-out first:

1. Protected page loads should perform one auth verification and one database request that returns the profile, roles, effective permissions, unread count, and basic navigation state.
2. Mutation handlers should perform one auth verification and either one required-permission check or call a transactional RPC that validates permission itself. They should not load all navigation permissions.
3. Keep simple single-table writes as normal Supabase writes. Keep existing transactional RPCs for orders, tickets, vouchers, stock, redemptions, and fulfilment.
4. Add Pages routing exclusions so static assets do not invoke the Worker.
5. Revoke unintended anonymous execution of `SECURITY DEFINER` functions before expanding the system.
6. Provision and bind R2 only when editable media is ready; it is currently planned in code but not enabled in the Cloudflare account.

After that correction, a normal protected page should fall from roughly 63–77 external calls to approximately 3–10, and the merchandise create action from roughly 63 to about 3. Those are request-count estimates, not promised latency figures.

## 2. Current architecture

### System diagram

```text
Australian browser
  |
  +-- static-looking or public URL ------------------------------+
  |                                                              |
  +-- portal/admin/API URL                                       v
       -> Cloudflare Pages advanced-mode _worker.js (Astro SSR)
            -> Supabase Auth /auth/v1/user
            -> Supabase PostgREST profile
            -> Supabase PostgREST role assignments
            -> 57 x Supabase PostgREST RPC has_permission
            -> unread notifications
            -> managed-child relationship
            -> page/action-specific PostgREST calls or RPCs
            -> rendered HTML or redirect
       <- Cloudflare response

Editable media path in source, but not operational:
Cloudflare worker -> R2 binding -> public media URL
                   X no live R2 bucket/binding
```

### Platform inventory

| Area | Current implementation | Evidence/status |
|---|---|---|
| Web framework | Astro 7, TypeScript, Tailwind | `package.json`, `astro.config.mjs` |
| Rendering | `output: "server"` through `@astrojs/cloudflare` | All Astro routes are server-capable |
| Cloudflare project | Pages project `website`, `website-4h5.pages.dev`, production branch `main` | Live Pages API |
| Cloudflare runtime | Advanced-mode `_worker.js`, `nodejs_compat`, `SESSION` KV | Repository and deployed config |
| Static routing | No built `_routes.json` | Static requests can enter the Worker by default |
| Supabase | Project `qzqezldtklimtupajvxf`, `ap-southeast-2`, Postgres 17.6 | Live project API |
| Auth | Supabase Auth with SSR cookie client | `src/lib/supabase/server.ts` |
| Authorisation | RLS plus roles, assignments, permission functions | Migrations and production schema |
| Service role | Used by selected admin/media/webhook/outbox paths | Server-only; no browser exposure found |
| Edge Functions | None deployed; no `supabase/functions` tree | Live list is empty |
| Scheduled database work | None | `pg_cron` not installed |
| Realtime | No subscriptions in code or live metrics | Not used |
| Supabase Storage | Zero buckets and objects | Not used |
| Cloudflare R2 | Helpers and planned environment variables only | R2 is not enabled; no binding |
| Payments | Manual mode plus Cloudflare webhook route contract | No live paid provider found |
| Email | Communication outbox claim/complete/fail contract | No provider or scheduler found |
| Images | Repository assets; editable upload helpers target R2 | No resizing/transcoding pipeline |
| QR | Server-generated QR data URLs for wallet/voucher views | Potential CPU hotspot; no CPU metric available |
| Audit | Database audit tables/triggers plus explicit route inserts | Some routes issue multiple separate audit writes |

### Actual request paths

**Protected page**

```text
Astro page
-> requirePortalSession / requireAdminSession
-> Supabase Auth getUser
-> profiles select("*")
-> user_role_assignments with role/team/season
-> Promise.all over 56 permission keys
-> wildcard has_permission RPC
-> unread notification count
-> managed child lookup
-> page-specific reads
-> PortalLayout receives the already-built session
-> SSR HTML
```

There is no middleware doing a second auth load and the layouts do not repeat it. The duplication is inside the session loader itself.

**Admin merchandise product create**

```text
POST handler in create-record flow
-> full protected request context (~62 Supabase calls)
-> validate submitted product fields
-> one merchandise_products insert
-> redirect to admin merchandise
```

Variant creation is a separate request and a separate insert. Image upload is a separate route. Product creation is not currently a multi-table transaction.

**Existing transactional operations**

```text
Cloudflare handler
-> shared session load (currently excessive)
-> one Postgres RPC
-> transaction updates related records and audit/fulfilment state
-> response
```

This pattern is already used for merchandise order creation, canteen ordering/completion, canteen benefit issuance, event-ticket ordering, voucher/wallet operations, and redemption. The database boundary is appropriate; the shared preamble is not.

**Public home**

```text
Cloudflare Astro SSR
-> content_articles
-> social_profiles
-> social_posts
-> teams list
-> teams HEAD exact count
-> sponsors
-> club_announcements
-> SSR HTML
```

Production logs confirmed these calls. Several run concurrently, but the home page still repeats the team request for a count and has no useful response cache.

### Configuration drift and major inefficiencies

- The live Pages build command rewrites `src/lib/supabase/server.ts` with an inline Node expression before running the build, then manually assembles `_worker.js`. This mutates source in the build environment and duplicates `scripts/prepare-pages-worker.mjs`.
- The repository compatibility date is `2026-04-15`; the live Pages project uses `2026-06-26`.
- The repository declares an `IMAGES` binding, but the live Pages binding inventory did not expose it.
- R2 variables and code exist, but the account reports that R2 is not enabled.
- No `_routes.json` is built, so immutable Astro assets and repository media may consume Worker invocations and asset-binding subrequests.
- Portal navigation is ordinary `<a>` navigation with full document reloads.
- Public pages perform multiple uncached Supabase calls per view.
- Several admin pages load broad datasets, use `select("*")`, or perform numerous exact count requests.

## 3. Measured performance

### Live public and redirect measurements

Measurements were made on the production Pages URL from the available environment. Values are individual samples, not a statistically significant benchmark. TTFB includes network distance from the measurement environment. Warm browser wall time and command-line TTFB were both sampled.

| Route | HTTP/effective route | TTFB | Total | HTML bytes | Browser warm wall sample | Notes |
|---|---:|---:|---:|---:|---:|---|
| `/` | 200 | 222 ms | 224 ms | 31,462 | 191 ms | At least 7 Supabase HTTP operations visible in logs |
| `/news/` | 200 | 205 ms | 205 ms | 12,401 | 90 ms | Content list query |
| `/teams/` | 200 | 106 ms | 106 ms | 12,762 | 98 ms | Team list plus related data |
| `/events/` | 200 | 95 ms | 95 ms | 9,528 | 115 ms | Public event query |
| `/merchandise/` | 200 | 105 ms | 105 ms | 10,852 | 449 ms first browser sample | Browser outlier was not reproduced by TTFB |
| `/portal/` | redirect to `/login/` | 89 ms | approximately 89 ms plus redirect handling | 13,324 final HTML | 104 ms | One redirect; unauthenticated |
| `/admin/` | redirect to `/login/` | 172 ms | approximately 172 ms plus redirect handling | 13,324 final HTML | 110 ms | One redirect; unauthenticated |

Cold-versus-warm Worker execution could not be separated from Cloudflare telemetry. The first and subsequent browser loads varied, but the sample is too small to label a cold-start penalty.

### Protected routes: current code-derived call budget

Protected route timings are unavailable because no authenticated test session was present. Counts below are current-code estimates and count external Supabase HTTP operations made by one Worker invocation. They exclude browser requests for HTML/assets and database-internal statements executed inside an RPC.

The common request context is approximately:

```text
1 Auth getUser
1 profile
1 role assignments
56 individual permission RPCs
1 wildcard permission RPC
1 unread notification count
1 managed-child lookup
= 62 external Supabase calls
```

| Requested area | Page-specific operations | Estimated Supabase HTTP calls | Edge Function calls | Internal site fetches | Storage/R2 | Likely bottleneck |
|---|---:|---:|---:|---:|---:|---|
| Portal dashboard | 8 reads | ~70 | 0 | 0 | 0 | Shared context, then page breadth |
| My Account | 1 read | ~63 | 0 | 0 | 0 | Shared context |
| Teams | 5 reads + 1 RPC | ~68 | 0 | 0 | 0 | Shared context; broad team data |
| Events | 2 reads | ~64 | 0 | 0 | 0 | Shared context |
| Shop | Disabled/redirecting route | ~62 before redirect if guarded | 0 | 0 | 0 | Shared context; feature not active |
| Orders | No standalone portal route | N/A | 0 | 0 | 0 | Orders are embedded in merchandise/wallet views |
| Portal merchandise | 2 reads | ~64 | 0 | 0 | 0 | Shared context |
| Wallet/vouchers | 8 reads | ~70 | 0 | 0 | 0 | Shared context plus server QR generation |
| Admin dashboard | 15 exact count reads | ~77 | 0 | 0 | 0 | Shared context and count fan-out |
| Admin canteen | 4 reads | ~66 | 0 | 0 | 0 | Shared context |
| Admin merchandise | 2 reads | ~64 | 0 | 0 | 0 | Shared context |
| Admin news | 1 read | ~63 | 0 | 0 | 0 | Shared context |
| Admin sponsors | 1 read | ~63 | 0 | 0 | 0 | Shared context |
| Admin users | 1 broad read | ~63 | 0 | 0 | 0 | Shared context and large result |
| Admin roles | 1 `select("*")` | ~63 | 0 | 0 | 0 | Shared context |

Every listed authenticated route exceeds Cloudflare Workers Free's 50-external-subrequest limit before or shortly after doing its page work. Concurrency reduces wall time but does not reduce the counted requests.

### Representative mutations

These counts are code-derived. Mutation timings were not measured against production.

| Mutation | Current database/provider work after context | Approx. external calls | Decision |
|---|---|---:|---|
| Create merchandise product | One table insert | ~63 total | Keep insert; fix action-specific auth |
| Update merchandise product | One update | ~63 total | Keep update; fix action-specific auth |
| Create variant | One insert in separate action | ~63 total | Keep insert; optionally support bulk variants later |
| Issue canteen vouchers/benefits | Existing `issue_canteen_benefits` RPC | ~63 total | Keep RPC; verify idempotency and grants |
| Complete canteen order | Existing completion RPC | ~63 total | Keep RPC |
| Create event | Simple event write plus route-specific audit as applicable | >62 | Direct write is acceptable if single-table |
| Claim/purchase ticket | Existing `create_event_ticket_order` RPC | ~63 total | Keep RPC for capacity/payment atomicity |
| Upload editable media | Service read, R2 put/delete, DB update, audit | Cannot work live: no R2 binding | Keep provider operations separate with compensation |
| Update sponsor | R2 put/delete, DB write, potentially multiple audit inserts | Usually several after context | Batch audit rows; R2 cannot join a DB transaction |
| Create social post | Direct database mutation and audit path | >62 | Keep simple write unless media is attached |

### Database timing evidence

- `has_permission`: 11,464 calls, 11.4 seconds total database time, about 0.995 ms mean.
- Role-assignment query family: 307 calls, about 1.86 ms mean.
- Profile query family: approximately 0.3 ms mean.
- A representative active-team plan used `teams_public_listing_idx`; execution was about 0.132 ms on the current empty/tiny relation. This confirms index use but is not predictive at scale.

The database is only 17 MB and most operational tables are empty. Current latency is not caused by table size. Network request count and SSR orchestration dominate.

## 4. Critical issues

### Critical

#### C1. Protected request context exceeds Cloudflare's hard subrequest limit

- **Evidence:** 57 `has_permission` calls plus five other context calls; production log burst; 11,464 historical function calls.
- **Files:** `src/lib/auth/session.ts` and every handler that calls its guards.
- **Routes:** all portal/admin pages and protected API routes.
- **Impact:** runtime failure, slow navigation, unnecessary Supabase API/egress load, poor scaling.
- **Correction:** add one effective-permissions/portal-context RPC for pages; add one `has_any_permission(required_keys[])` check for simple actions or validate inside transactional RPCs. Memoise the result only for the current request.

#### C2. Anonymous execution surface on privileged database functions

- **Evidence:** Supabase security advisor and production privilege inspection identify 13 anon-executable `SECURITY DEFINER` functions, including wallet, webhook, notification, voucher, team, and volunteer operations.
- **Affected functions:** `adjust_wallet_balance`, `create_wallet_top_up`, `enqueue_admin_notification`, `ensure_wallet_account`, `process_payment_webhook`, `process_wallet_qr_purchase`, `request_volunteer_shift`, `reverse_wallet_ledger_entry`, `settle_wallet_top_up`, `update_volunteer_assignment`, and `update_volunteer_shift_status`.
- **Impact:** confirmed exposure through PostgREST. Exploitability depends on each function's internal checks, but service-only functions being callable by `anon` is an unacceptable attack surface.
- **Correction:** revoke execute from `PUBLIC` and `anon` for every function by exact signature; grant only `authenticated` or `service_role` as justified. Verify `auth.uid()`, permission checks, safe `search_path`, input validation, idempotency, and audit behaviour.

### High

#### H1. All static paths can invoke the advanced-mode Worker

- **Evidence:** built output contains `_worker.js` but no `_routes.json`.
- **Files:** `scripts/prepare-pages-worker.mjs`, `public/`, deployment output.
- **Impact:** static assets unnecessarily consume Worker requests and possibly asset-binding work; avoidable pressure on the 100,000 request/day free allowance.
- **Correction:** generate and test `_routes.json` exclusions for `/_astro/*`, versioned media, and genuinely static pages. Include `/portal/*`, `/admin/*`, `/api/*`, auth routes, and dynamic public content.

#### H2. Live Pages build mutates source and drifts from repository configuration

- **Evidence:** live build command performs an inline replacement in `src/lib/supabase/server.ts`, then duplicates worker assembly; compatibility dates differ.
- **Impact:** deployment is difficult to reproduce, source behaviour differs by environment, and future R2/runtime binding access can break.
- **Correction:** make repository code read runtime bindings correctly without build-time rewriting; use one checked-in build/postbuild path; align compatibility date and bindings.

#### H3. Service-role client is used for ordinary admin reads

- **Evidence:** admin merchandise and canteen pages and selected media routes construct service clients.
- **Impact:** bypasses RLS unnecessarily and makes route-level guards the only boundary.
- **Correction:** use the user-scoped server client and RLS for normal admin reads/CRUD. Retain service role for trusted webhooks, Auth administration, outbox workers, and operations that genuinely require bypass.

#### H4. Public home is an uncached multi-request SSR aggregate

- **Evidence:** production logs show articles, social profile/post, teams plus a duplicate HEAD count, sponsors, and announcements per load.
- **Impact:** unnecessary Supabase requests and slower TTFB for the highest-volume page.
- **Correction:** remove the duplicate team count, preserve safe concurrency, and add short public response/data caching. Consider one aggregate RPC only if measurement shows the remaining round trips matter.

#### H5. R2 media architecture is referenced but not provisioned

- **Evidence:** Cloudflare reports R2 not enabled; no live binding; Supabase Storage is also empty.
- **Impact:** editable media routes cannot operate as designed.
- **Correction:** after the auth incident is fixed, enable R2 Standard, create explicit public/private buckets and bindings, configure a production public domain, and test runtime binding access. Do not ship an `r2.dev` development URL as the permanent public media origin.

### Medium

#### M1. Admin and portal pages overfetch and fan out

- **Evidence:** `select("*")` in session profiles and admin roles; admin dashboard issues 15 exact counts although `admin_dashboard_summary` already exists; several list pages request 80–300 records and filter in JavaScript.
- **Impact:** larger responses and additional calls as data grows.
- **Correction:** select required columns, use the existing summary RPC, apply SQL filters, and paginate.

#### M2. RLS policy and foreign-key index advisories

- **Evidence:** 41 `auth_rls_initplan` warnings, 44 unindexed foreign keys, and 18 multiple-permissive-policy warnings.
- **Impact:** avoidable per-row auth evaluation and future join/delete degradation.
- **Correction:** rewrite policy helpers to `(select auth.uid())`/equivalent, consolidate overlapping policies carefully, and add indexes in query-driven order.

#### M3. Portal navigation performs full document reloads

- **Evidence:** `src/layouts/PortalLayout.astro` uses ordinary anchors; no Astro ClientRouter/View Transitions.
- **Impact:** repeated document and shell rendering makes backend latency visible.
- **Correction:** fix backend request count first, then consider Astro's native client router/view transitions for shell continuity. Do not turn the portal into a large SPA.

#### M4. Image payloads are not production-optimised

- **Evidence:** hero PNG is about 2.09 MB at 1672×941; logo is about 642 KB at 960×960 but displayed near 56×56; uploads accept up to 10 MB without dimension checks, resizing, or transcoding.
- **Impact:** slower visual loading and wasteful bandwidth.
- **Correction:** generate right-sized WebP/AVIF variants, use responsive markup, hash/version immutable assets, validate dimensions, and build thumbnails on upload.

#### M5. Server QR generation may consume scarce CPU

- **Evidence:** wallet/voucher route generates QR data URLs during SSR; Cloudflare Free CPU is limited.
- **Impact:** possible CPU and response-size pressure when many codes are displayed.
- **Correction:** measure CPU after observability is enabled; generate QR codes lazily/client-side from a safe opaque presentation token or cache safe rendered output. Never expose raw redemption secrets in logs.

### Low

- `public/_headers` gives `/media/*` only a one-day cache. Versioned immutable public media can use a year; mutable unversioned URLs cannot.
- Leaked-password protection is disabled in Supabase Auth. Enable it subject to the chosen Auth plan and user communication.
- There are 110 “unused index” advisories, but this production database is new and tiny. Do **not** remove indexes based on this signal yet.

## 5. Cloudflare subrequest incident

### Exact cause

The failing action is the generic create-record path for `merchandiseProduct`. The action calls the protected session/permission guard and then inserts one `merchandise_products` row.

The guard performs:

| Work | Destination | Calls | Necessary? |
|---|---|---:|---|
| Verify access token/user | Supabase Auth | 1 | Yes |
| Read profile | PostgREST | 1 | Yes, but narrow columns |
| Read role assignments | PostgREST | 1 | Yes, but can be aggregated |
| Check each known permission | PostgREST RPC | 56 | No; combine |
| Check wildcard permission | PostgREST RPC | 1 | No separate request |
| Count unread notifications | PostgREST | 1 | Useful for page navigation, not this action |
| Read managed child | PostgREST | 1 | Useful for page context, not product creation |
| Insert product | PostgREST | 1 | Yes |
| **Total** |  | **~63** |  |

The current Workers Free limit is 50 external subrequests per invocation. See [Cloudflare Workers limits](https://developers.cloudflare.com/workers/platform/limits/) and the [2026 subrequest-limit changelog](https://developers.cloudflare.com/changelog/post/2026-02-11-subrequests-limit/).

### What is not causing it

- No image operation runs as part of basic product creation.
- No variants or stock rows are inserted by that action.
- There is no per-field product audit loop in this path.
- The Worker does not fetch its own internal route.
- The redirect is an outbound response; following it creates another Worker invocation.
- Database execution of `has_permission` is fast; repeated HTTP calls are the problem.

### Redesign

For a simple product insert:

```text
Cloudflare action
-> Supabase Auth getUser
-> one has_any_permission(["merchandise.manage", ...]) RPC
-> one merchandise_products insert under user-scoped RLS
-> redirect
```

Expected external calls: approximately three.

An even stronger design is a product mutation RPC only if product creation later becomes a genuine multi-table transaction. That RPC should validate the caller, insert the product and any explicitly submitted variants/stock in one transaction, record one audit event, and accept an idempotency key if retries are possible. The current single-row create does not justify that complexity.

Bulk operations are appropriate only when the UI submits multiple variants, stock adjustments, recipient assignments, or audit rows. R2 upload/delete must remain outside a Postgres transaction and use compensation if the following DB update fails.

An Edge Function is not appropriate here: it would add another provider hop without improving transactionality or authorisation.

## 6. Recommended responsibility matrix

| Operation | Current location | Recommended location | Reason | Expected benefit |
|---|---|---|---|---|
| Public page reads | Cloudflare SSR -> PostgREST | Same, parallel and short cached; aggregate only proven hot pages | Simple reads and CDN-friendly output | Fewer calls and faster TTFB |
| Portal reads | Cloudflare SSR -> direct PostgREST | Same with one shared request context, narrow/paginated reads | Keeps RLS and simple architecture | ~59 fewer base calls |
| Auth context | Many Supabase HTTP calls | Auth getUser + one `get_portal_context` RPC | One authoritative snapshot per request | Lower latency and subrequests |
| Permission check for actions | Full navigation permission load | One `has_any_permission` RPC or check inside transaction RPC | Least work and current server enforcement | ~57 fewer calls/action |
| Product creation/update | Direct insert/update | Keep direct while single-table | RPC would add needless complexity | Simple and secure |
| Variant creation | One insert per submitted action | Keep one insert; use one bulk insert for batch UI | Bulk only when truly batched | Removes future N+1 |
| Stock update/reservation | Existing DB operations/RPCs | Transactional Postgres RPC | Concurrency and atomicity | Correct stock under load |
| Merchandise orders | Existing `create_merchandise_order` RPC | Keep | Multi-table transactional work | Correctness and one HTTP call |
| Free event ticket | Existing ticket-order RPC | Keep/extend with idempotency | Capacity and issuance must be atomic | Prevents over-issue |
| Paid event ticket | RPC plus payment state | Database order RPC; provider webhook at Cloudflare route | DB transaction plus external signature boundary | Reliable fulfilment |
| Wallet voucher issuance | Existing RPCs | Keep; use batch RPC for recipient expansion | Atomic ledger/voucher changes | One request and idempotency |
| QR redemption | Existing RPC | Keep | Requires row locking, one-time status and audit | Prevents double redemption |
| Emails | Outbox contract, no sender | External worker/Edge Function only when provider configured | Private credential, retry, external I/O | Durable delivery without page blocking |
| Payment webhooks | Cloudflare server route + service RPC | Keep at Cloudflare; add provider-native signature/replay checks | Already at ingress, no Edge hop needed | Secure and lower complexity |
| Scheduled jobs | None | Postgres cron for DB-only work; one external worker/function for provider work | Put work closest to its dependencies | Avoids unnecessary runtimes |
| Image upload | Cloudflare route -> planned R2 -> DB | Keep at Cloudflare/R2; validate and transform; compensate failures | R2 binding is local to Cloudflare | Lower egress and simpler media path |
| Audit tied to transaction | Mixed triggers/RPC and route writes | Inside the same RPC/trigger | Cannot diverge from data mutation | Integrity and fewer calls |
| Audit for R2/external side effect | Route-level separate inserts | One batched insert after final outcome | External work cannot share DB transaction | Fewer requests, clear outcome |

## 7. Supabase RPC candidates

| Function | Purpose/tables | Permission model | Idempotency | Implement? |
|---|---|---|---|---|
| `get_portal_context()` | Profile, role assignments, effective permission keys, unread count, managed-child summary | Prefer `SECURITY INVOKER`; if definer is required, authenticated-only grant, explicit `auth.uid()`, safe `search_path` | Read-only | **Yes, first** |
| `has_any_permission(required_keys text[], team_id uuid, season_id uuid)` | One action-specific permission decision | Authenticated only; validate `auth.uid()`; no client role claims | Read-only | **Yes** |
| `admin_dashboard_summary()` | Replaces 15 exact-count HTTP calls | Existing function; verify authenticated admin permission and grants | Read-only | **Use existing** |
| `create_merchandise_order(...)` | Order, items, stock reservation, totals, audit | Existing server-validated caller and trusted server pricing | Required request key | **Keep existing** |
| `create_canteen_order(...)` | Order/items/prices/stock | Existing authenticated checks; price from DB | Required for retries | **Keep existing** |
| `complete_canteen_order(...)` | Status, fulfilment, audit/benefits | Staff permission inside function | Required | **Keep existing** |
| `issue_canteen_benefits(...)` | Batch vouchers/assignments | Staff permission; recipient ownership validated | Existing/request key required | **Keep existing** |
| `create_event_ticket_order(...)` | Capacity, order, ticket issuance/payment state | Caller ownership; prices/capacity from DB | Required | **Keep existing** |
| `redeem_event_ticket(...)` | One-time ticket redemption | Staff permission and row lock | Ticket state is idempotency boundary | **Keep existing** |
| `process_wallet_qr_purchase(...)` | Wallet debit, purchase, redemption/audit | Authenticated terminal/user rules, locking | Required | **Keep, fix grants** |
| `batch_insert_audit_events(jsonb)` | Multiple route audit entries | Server/admin only; strict schema | Route operation ID | **Only if batching remains common** |
| `save_merchandise_product_bundle(...)` | Product plus variants/initial stock | Admin permission, typed arrays, safe prices | Required | **Not now**; current create is one row |
| `update_sponsor_with_audit(...)` | Sponsor metadata plus DB audit | Admin permission | Optional operation ID | **Maybe**; R2 still remains separate |

All new functions need explicit signature grants. Revoke `PUBLIC` first, then grant only the intended role. Use structured return values and stable error codes rather than leaking arbitrary SQL text. Do not trust browser-calculated totals, stock, roles, or ownership.

## 8. Edge Function decisions

The production inventory contains **zero Supabase Edge Functions**, so there are no deployed functions to classify as keep/move/remove. The repository also has no `supabase/functions` implementation.

| Potential workflow | Decision | Reason |
|---|---|---|
| Ordinary portal/admin CRUD | Do not add an Edge Function | Direct RLS query or Postgres RPC is faster and simpler |
| Payment provider callback | Keep current Cloudflare route | It is already the public ingress and can call one service-role fulfilment RPC |
| Email delivery | Add one external worker or Edge Function only when a provider is selected | Requires a private provider credential, retries, and outbox processing |
| External scheduled workflow | Edge Function or Cloudflare scheduled Worker, selected by credential/runtime locality | Appropriate only for external I/O |
| DB-only expiry/cleanup | Scheduled Postgres job if/when enabled | Avoids network and another runtime |
| Product/order/ticket/voucher transactions | Postgres RPC | Pure transactional database work |

Moving a database-only operation into a Supabase Edge Function would produce:

```text
Cloudflare -> Supabase Edge gateway -> Postgres -> Edge -> Cloudflare
```

That is an extra provider/runtime boundary with no transactional advantage.

## 9. Database optimisation

### Current production state

- Database size: about 17 MB.
- Auth users: 2.
- All inspected public tables report RLS enabled.
- Operational data is sparse: most order, ticket, voucher, and membership tables have zero rows.
- `pg_stat_statements` is enabled; `pg_cron` is not.
- Security advisor notices: 33.
- Performance advisor notices: 213, including 44 unindexed foreign keys, 41 auth-initplan policies, 110 unused-index notices, and 18 multiple-permissive-policy cases.

### Indexes to add, in measured/query-driven order

Do not add all 44 mechanically. Start with foreign keys and filters that appear in operational routes or delete/update paths:

- `merchandise_order_items(product_id)`
- `merchandise_order_status_history(order_id)` and, if frequently filtered, `(order_id, created_at desc)`
- `merchandise_order_status_history(changed_by)`
- `canteen_order_items(voucher_issuance_id)`
- `canteen_orders(completed_by)`
- event order/payment/ticket foreign keys used by fulfilment and redemption
- managed-child indexes on family/manager relationships
- family voucher/assignment child and family keys
- team post/reaction/read/poll response foreign keys on post, option, and user/respondent
- voucher issuance indexes on campaign/template/assigned_by

Before each migration, match the index to the actual query predicate and sort. Use partial indexes only where the active subset is selective, for example unresolved notifications or active/unexpired tokens. Validate with `EXPLAIN (ANALYZE, BUFFERS)` on a staging dataset large enough to be meaningful.

### Indexes not to remove yet

The 110 unused-index warnings are dominated by a new, nearly empty database. Retain:

- primary/unique and constraint-supporting indexes;
- foreign-key indexes;
- indexes serving security policies, idempotency keys, token uniqueness, active listings, and future order state;
- indexes with zero scans until at least 30–90 days of representative production traffic is available.

### RLS policy improvements

Forty-one policies repeatedly initialise auth expressions per row. Replace patterns such as:

```sql
auth.uid() = user_id
```

with the init-plan-friendly form:

```sql
(select auth.uid()) = user_id
```

where semantics are identical. Apply to the reported policies on access requests, managed children, store/wallet QR tokens, polls, vouchers, wallets and ledger, match reports, canteen orders/items, team content, notifications, event registrations, family assignments, payments, and notification preferences.

There are multiple permissive policies on events, registrations, fixtures, notifications, social content, training, volunteer assignments, vouchers, and templates. PostgreSQL ORs permissive policies. Consolidate equivalent branches only after role/ownership regression tests; fewer policies are not automatically safer.

### Functions and privileges

1. Revoke unintended public/anonymous execute privileges by exact function signature.
2. Keep `SECURITY DEFINER` only when bypassing caller RLS is essential.
3. Set an explicit safe search path (for example `pg_catalog, public, app_private` as required) and schema-qualify objects.
4. Perform `auth.uid()` and permission checks inside every exposed privileged function.
5. Move internal helpers into a non-exposed schema where possible.
6. Ensure webhook/queue functions are `service_role` only.

### Query corrections

| File/area | Current behaviour | Correction |
|---|---|---|
| `src/lib/auth/session.ts` | `profiles.select("*")`; 57 permission RPCs | Narrow columns; one context RPC |
| Admin dashboard | 15 exact counts | Call existing `admin_dashboard_summary` once |
| Admin roles | `select("*")` | Request only displayed/editable columns |
| Admin users/news/coaching | Fetches large fixed batches and filters in JS | SQL filters plus cursor/offset pagination |
| Portal teams | Multiple broad datasets then JS filtering | Keep parallel initially; move search/status filtering to SQL as data grows |
| Public home helpers | Duplicate teams HEAD count | Derive count from fetched list or combine |
| Sponsor/media routes | Service read, DB update, repeated audits | User-scoped RLS where possible; batch audit |

The safe plan check of the public teams listing used `teams_public_listing_idx` and completed in approximately 0.132 ms on current data. This is evidence of index use, not evidence that all future queries are optimised.

## 10. Cloudflare recommendations

### Pages and Worker configuration

1. **Keep Cloudflare Pages and Astro SSR.** The platform is compatible and current public TTFB is reasonable.
2. **Create `_routes.json`.** Exclude `/_astro/*` and immutable/versioned repository media from the Worker. Include protected, API, authentication, and truly dynamic SSR paths. Cloudflare documents advanced-mode routing in [Pages Functions routing](https://developers.cloudflare.com/pages/functions/routing/).
3. **Remove the live build-time source rewrite.** Fix `src/lib/supabase/server.ts` to read the supported Cloudflare runtime environment in repository code and use the single postbuild script.
4. **Align deployed and repository compatibility dates and bindings.**
5. **Enable observability.** Record route, status, total duration, and safe `Server-Timing` components such as `auth`, `context`, `db`, and `render`. Never log tokens, secrets, complete QR tokens, private records, or payment payloads.

### Subrequests and CPU

- Target fewer than 10 external calls for ordinary pages and fewer than 5 for simple mutations.
- Do not use internal route-to-route `fetch` for shared logic; call a library function or database operation directly.
- Measure QR generation CPU and move nonessential batch rendering out of the initial SSR response if it approaches the 10 ms free CPU limit.
- The current daily Worker-request count and CPU/error series were unavailable. Enable Pages Functions metrics described in [Cloudflare Pages metrics](https://developers.cloudflare.com/pages/functions/metrics/).

### Caching

- Cache public sponsors, news listings, social profiles/posts, public events, products, categories, and stable club configuration for 30–300 seconds according to change frequency.
- Use versioned URLs and long immutable caching for static images.
- Do not broadly cache permissions, account data, balances, orders, vouchers, stock during checkout, redemption, tickets, or payment state.
- Purge or version public cached objects when an admin writes them.

### Smart Placement

Supabase is in Sydney and most users are Australian. Cloudflare's default nearest-user execution will commonly already be close to both. Smart Placement may therefore provide little benefit and could make static routing less intuitive if enabled before `_routes.json` is fixed. After reducing subrequests, compare p50/p95 backend timing with and without Smart Placement. Enable it only if measurements improve. See [Smart Placement for Pages](https://developers.cloudflare.com/pages/functions/smart-placement/) and [Workers placement](https://developers.cloudflare.com/workers/configuration/placement/).

### R2

The proposed split is sound after provisioning:

```text
Fixed branding -> repository / Cloudflare static assets
Editable public media -> R2 Standard public bucket through a production domain
Private media -> separate private R2 bucket, authorised short-lived delivery
```

Add MIME allowlisting, magic-byte validation, size and dimension limits, image transcoding, thumbnail/responsive variants, object-key randomisation, and database metadata. A private object must never be exposed merely by knowing its key. R2's current free allowance is 10 GB-month storage, 1 million Class A operations, and 10 million Class B operations, with free egress; see [R2 pricing](https://developers.cloudflare.com/r2/pricing/).

## 11. Vercel decision

### Decision: Stay on Cloudflare

Astro SSR is supported on both platforms. Vercel would likely accept more outbound calls per function and thereby hide the immediate 50-subrequest failure. It would not eliminate:

- 57 separate permission HTTP calls;
- the observed request-context delay;
- Supabase API/egress consumption;
- full document navigation;
- broad queries;
- missing media processing;
- the database-function privilege findings.

Vercel Hobby also has personal/non-commercial restrictions that need organisational review, and function region defaults/configuration would need explicit attention so compute does not move away from the Sydney Supabase project. See [Vercel Hobby](https://vercel.com/docs/plans/hobby), [function regions](https://vercel.com/docs/functions/configuring-functions/region), [function limits](https://vercel.com/docs/functions/limitations), and [Astro's Vercel deployment guide](https://docs.astro.build/en/guides/deploy/vercel/).

Migration would require an adapter change, deployment/environment reconfiguration, replacing Cloudflare runtime/KV/R2 bindings, regression testing cookies and SSR, and rebuilding observability. After the request architecture is corrected, there is no measured performance benefit that justifies this work.

**Direct answer:** moving from Cloudflare to Vercel would not materially improve this application after the current architecture is corrected. Revisit hosting only if measured production load, reliability requirements, commercial plan terms, or team workflow—not this code-level fan-out—create a new constraint.

## 12. Free-tier plan

Platform allowances change; verify them before a purchasing decision. Current references include [Cloudflare Workers limits](https://developers.cloudflare.com/workers/platform/limits/), [Pages limits](https://developers.cloudflare.com/pages/platform/limits/), [Pages pricing](https://developers.cloudflare.com/pages/functions/pricing/), [Supabase pricing](https://supabase.com/pricing), [database size](https://supabase.com/docs/guides/platform/database-size), [egress](https://supabase.com/docs/guides/platform/manage-your-usage/egress), [MAU](https://supabase.com/docs/guides/platform/manage-your-usage/monthly-active-users), and [Edge Function limits](https://supabase.com/docs/guides/functions/limits).

| Resource | Current usage | Free allowance | Risk | Recommended action | Upgrade trigger |
|---|---:|---:|---|---|---|
| Cloudflare Worker requests | Unavailable | 100,000/day | Medium until static routing fixed | Add `_routes.json`; enable metrics | Sustained 70–80k/day after exclusions, or reliability needs |
| Worker external subrequests | ~63–77/protected request | 50/invocation | **Critical now** | Consolidate auth/permissions immediately | Do not upgrade as first fix |
| Worker CPU | Unavailable | 10 ms/request free | Medium for QR-heavy page | Measure CPU; lazy QR generation if needed | Repeated CPU-limit errors after optimisation |
| Pages builds | Current deployment active; exact monthly count unavailable | 500/month | Low | Keep normal main-branch deployment | Sustained >400/month |
| Pages assets | 30 built client files; ~5.47 MB total, max asset ~2.1 MB | 20,000 files, 25 MiB/file | Low | Optimise media for users, not quota | Approaching 80% of file/count limits |
| R2 | 0; not enabled | 10 GB-month, 1M Class A, 10M Class B | Low now; blocking feature | Provision deliberately and monitor operations | >8 GB or >80% monthly operations |
| Supabase database | ~17 MB | 500 MB free | Low | Monitor monthly; keep indexes/query plans healthy | 350–400 MB or operational need for backups/PITR |
| Supabase Auth | 2 users | 50,000 MAU free | Low | Enable security features; monitor MAU | 40,000 MAU or feature/support requirement |
| Supabase egress | Exact usage unavailable | 5 GB uncached + 5 GB cached cited for Free | Medium because of request fan-out | Remove 57 repeated calls; monitor dashboard | 70–80% sustained |
| Supabase Storage | 0 buckets/objects | 1 GB free | Low | Continue with R2 plan unless Supabase-native policy delivery is preferred | N/A under current plan |
| Supabase Edge Functions | 0 deployed/invocations | 500,000 invocations free | Low | Add only for genuine external workflow | >400,000 or execution/resource need |
| Realtime | 0 | Plan-dependent quota | Low | Do not add without a product need | Sustained connection/message growth |
| Email provider | None configured | Unknown | Feature risk, not quota risk | Select provider and document retry/bounce limits | Provider-specific 70–80% |
| Payment provider | Manual/no production provider found | Provider-specific | Low usage; high correctness concern | Implement signed webhook before paid flow | Provider/business volume threshold |

The likely first hard limit is already reached: **external subrequests per protected invocation**. After correction, the next avoidable risk is wasting Worker requests on static assets. At expected small-club usage, the system can reasonably remain on the free tiers, but production backup/PITR, support, SLA, or organisational needs can justify upgrading before raw quotas are exhausted.

Do not create extra free accounts to avoid legitimate growth costs.

## 13. Target architecture

```text
Cloudflare Pages
├─ Static delivery
│  ├─ /_astro/* immutable, Worker excluded
│  └─ versioned fixed club branding, Worker excluded
├─ Astro SSR
│  ├─ public dynamic pages with 30–300s safe caching
│  ├─ protected portal/admin pages
│  └─ protected API/action handlers
├─ Request context
│  ├─ one Supabase Auth verification
│  └─ one get_portal_context RPC for page navigation
├─ Action authorisation
│  └─ one required-permission RPC or permission inside transaction RPC
└─ R2
   ├─ public editable media, transformed and versioned
   └─ private media through authorised delivery

Supabase Sydney
├─ Auth
├─ Postgres
│  ├─ RLS for user-scoped reads and simple CRUD
│  ├─ narrow, paginated PostgREST queries
│  ├─ transactional RPCs for orders/stock/tickets/wallet/redemption
│  ├─ transaction-coupled audit logging
│  └─ least-privilege function grants
└─ No Edge Function by default
   └─ add only for shared external integrations if Cloudflare is not the better ingress

External providers
├─ Payment callback -> Cloudflare signed webhook -> one service-role RPC
└─ Email worker -> claim outbox -> provider -> mark outcome
```

### Region and network path

Confirmed Supabase services are in `ap-southeast-2` (Sydney). There are no Edge Functions, storage objects, email provider, or paid payment provider to place. Exact Cloudflare colocation for an individual request was not exposed.

Current protected path:

```text
Sydney user
-> nearby Cloudflare runtime (likely, not guaranteed)
-> Supabase Auth Sydney
-> Cloudflare
-> Supabase PostgREST Sydney, repeated ~61 more times
-> Cloudflare
-> user
```

Target:

```text
Sydney user
-> Cloudflare
-> Supabase Auth Sydney (1)
-> Supabase PostgREST/RPC Sydney (1 context + 1–8 page operations)
-> Cloudflare
-> user
```

Avoid a Supabase Edge Function wrapper for database-only work because it introduces another gateway/runtime boundary. Smart Placement should be tested only after call consolidation; users and database are already geographically aligned.

### Cache policy

| Data | Cache recommendation |
|---|---|
| Sponsors, social content, public news/events/products/categories/config | Browser/CDN/server cache 30–300s, with purge/version on write |
| Fixed/versioned images | One year immutable |
| Request user/profile/navigation context | Memoise for one Worker request only |
| Permissions used to authorise a mutation | Fresh server/RPC check; never trust navigation cache |
| Wallet, orders, vouchers, redemptions, payment, live stock | No broad cache |

## 14. Implementation plan

This is the exact risk-minimising order proposed after owner approval.

1. **Capture a reproducible authenticated baseline.**  
   **Systems/files:** Cloudflare Pages observability, a non-production test user, safe timing helper in `src/lib/`.  
   **Migration:** none.  
   **Tests:** portal/admin route matrix; product create in preview; record subrequests, p50/p95 TTFB, CPU, and failures.  
   **Rollback:** remove or disable timing flag.  
   **Benefit:** establishes a defensible before/after record without logging sensitive values.

2. **Lock down database function execution grants.**  
   **Systems/files:** new Supabase migration covering exact function signatures; function tests.  
   **Migration:** revoke from `PUBLIC`/`anon`; explicit authenticated/service grants; correct safe search paths where missing.  
   **Tests:** anonymous calls fail; intended user/service calls pass; ownership, permission, QR, webhook, and audit regression tests.  
   **Rollback:** restore only the previous explicit grants per signature, never blanket `PUBLIC`.  
   **Benefit:** closes the highest-risk optimisation-adjacent security exposure.

3. **Add aggregate request context.**  
   **Systems/files:** new migration for `get_portal_context`; `src/lib/auth/session.ts`; generated database types.  
   **Migration:** read-only function returning narrow profile fields, roles, unique effective permission keys, unread count, and child/navigation summary.  
   **Tests:** compare old/new context for super admin, limited member, team-scoped role, inactive assignment, managed child, and no-role user.  
   **Rollback:** retain old loader behind a temporary environment flag for one deployment.  
   **Benefit:** page base from ~62 to ~2 external calls.

4. **Separate page context from action authorisation.**  
   **Systems/files:** auth/action guard helpers and protected API/action handlers.  
   **Migration:** add `has_any_permission(required_keys[], optional scope)` if existing `has_permission` cannot take a set.  
   **Tests:** deny-by-default, wildcard, team/season scope, expired assignments, and forged form fields.  
   **Rollback:** switch handlers back to old guard temporarily.  
   **Benefit:** simple mutations from ~63 to ~3 calls; removes the current Cloudflare failure.

5. **Use the existing dashboard summary RPC and remove broad shared reads.**  
   **Systems/files:** admin dashboard page; session profile column list; admin roles/users/news/coaching queries.  
   **Migration:** none unless the existing summary return type needs a safe extension.  
   **Tests:** count parity and pagination/filter behaviour.  
   **Rollback:** individual counts remain easy to restore.  
   **Benefit:** admin dashboard from ~77 toward ~3 calls; smaller payloads.

6. **Add Pages routing exclusions.**  
   **Systems/files:** `scripts/prepare-pages-worker.mjs`, generated `dist/client/_routes.json`, deployment tests.  
   **Migration:** none.  
   **Tests:** static assets return directly with expected cache headers; portal/admin/API/auth paths still invoke SSR; public dynamic pages remain current.  
   **Rollback:** remove/narrow exclusions.  
   **Benefit:** protects the 100k/day Worker allowance and lowers static latency.

7. **Eliminate deployment drift.**  
   **Systems/files:** `src/lib/supabase/server.ts`, `package.json`, postbuild script, Pages build settings, `wrangler.jsonc`.  
   **Migration:** none.  
   **Tests:** local and preview build with runtime vars/KV; preview login; future binding smoke test.  
   **Rollback:** previous Pages deployment remains available.  
   **Benefit:** reproducible deployment and safer binding support.

8. **Cache safe public content and remove duplicate home calls.**  
   **Systems/files:** `src/lib/public-content.ts`, public route response headers/cache helpers.  
   **Migration:** none.  
   **Tests:** expiry and purge/version behaviour; private headers never cached; admin edits appear within agreed TTL.  
   **Rollback:** set cache TTL to zero.  
   **Benefit:** lower public TTFB, Worker/Supabase request and egress usage.

9. **Apply query-driven RLS and index migrations.**  
   **Systems/files:** new migrations for init-plan rewrites and high-value foreign-key indexes.  
   **Migration:** small reviewed batches using concurrent index creation where production tooling supports it.  
   **Tests:** RLS role/ownership matrix and before/after plans on representative seeded data.  
   **Rollback:** policy definitions captured verbatim; indexes can be removed individually if proven harmful.  
   **Benefit:** protects performance as operational tables grow.

10. **Reduce service-role use and audit fan-out.**  
    **Systems/files:** admin merchandise/canteen and sponsor/media routes; audit helper/RPC if justified.  
    **Migration:** RLS policy correction only where current legitimate admin access is absent.  
    **Tests:** admin succeeds, ordinary member/anon fails, audit completeness, R2 compensation paths.  
    **Rollback:** restore route-level service client while correcting policy, with guard retained.  
    **Benefit:** stronger defence-in-depth and fewer database calls.

11. **Provision the media architecture.**  
    **Systems/files:** Cloudflare R2 buckets/bindings, `src/lib/media.ts`, upload routes, image components, cache headers.  
    **Migration:** media metadata/variant fields only if necessary.  
    **Tests:** type/magic-byte/size/dimension rejection, transform output, private authorisation, orphan cleanup and rollback compensation.  
    **Rollback:** keep repository assets; disable editable upload feature flag.  
    **Benefit:** makes planned uploads operational and cuts image bandwidth.

12. **Improve navigation perception only after backend targets pass.**  
    **Systems/files:** `src/layouts/PortalLayout.astro`, route transitions, page-specific scripts.  
    **Migration:** none.  
    **Tests:** history, focus, scroll, forms, authentication redirects, no stale private document, accessibility.  
    **Rollback:** ordinary anchors.  
    **Benefit:** smoother shell continuity; it does not replace backend optimisation.

13. **Implement external providers when selected.**  
    **Systems/files:** payment webhook route, communication outbox worker, provider configuration/runbooks.  
    **Migration:** webhook event/idempotency and outbox lease fields if not already sufficient.  
    **Tests:** raw-body signature, timestamp/replay rejection, duplicate webhook, retry, dead-letter/manual recovery, no secret logging.  
    **Rollback:** retain manual payment/email mode.  
    **Benefit:** secure reliable integrations without blocking user requests.

## 15. Estimated outcome

| Flow | Current estimate | Target estimate | Basis |
|---|---:|---:|---|
| Protected page base context | ~62 external calls | ~2 | Auth plus one context RPC |
| Typical protected page | ~63–70 | ~3–10 | Context plus existing page reads |
| Admin dashboard | ~77 | ~3 | Auth, context, existing summary RPC |
| Product create/update | ~63 | ~3 | Auth, one permission decision, one write |
| Existing transactional mutation | ~63+ | ~3 | Auth, permission/context, one RPC |
| Public home | 7+ | 1 cached response on hit; fewer origin calls on miss | CDN caching and duplicate removal |

Expected effects:

- The Worker subrequest error should be eliminated for normal routes because requests move comfortably below 50.
- Protected requests should make roughly 85–97% fewer Supabase HTTP calls, depending on page breadth.
- Database execution time may not change dramatically per statement; total provider round trips and API overhead will.
- The observed 1.4-second auth/permission log cluster should collapse to a small number of calls. A precise TTFB improvement cannot be promised until authenticated before/after traces exist.
- Public caching and static routing exclusions will reduce Cloudflare Worker invocations and Supabase egress.
- RLS/index work will mostly protect future scale because the current 17 MB database is too small for those improvements to dominate today.
- Image optimisation should materially improve visual load, especially the 2.09 MB hero and oversized logo, but image-specific browser timing was not captured in this review.

## 16. Final recommendation

1. **Should the project remain on Cloudflare?**  
   Yes. Cloudflare Pages remains suitable after request fan-out and static routing are corrected.

2. **Should any part move to Vercel?**  
   No. There is no measured technical benefit that justifies migration. Vercel would mask one limit while preserving the inefficient architecture.

3. **Which operations belong in Postgres RPCs?**  
   Aggregate portal context, a set-based permission decision, admin summary, and multi-table transactions involving orders, stock, tickets, wallet ledger, vouchers, redemption, fulfilment, and transaction-coupled audit. Simple product/news/sponsor metadata CRUD should remain normal RLS-protected writes unless it becomes multi-table.

4. **Which Edge Functions should remain?**  
   None currently exist. Add one only for a genuine external integration shared across clients or requiring a private third-party credential/retry runtime. The Cloudflare payment webhook can remain on Cloudflare; pure database work belongs in Postgres.

5. **What is causing the current portal slowness?**  
   The confirmed primary cause is the protected session loader issuing 57 permission RPC HTTP requests plus profile, role, notification, and child lookups on every page/action. Full-document Astro navigation exposes that latency. Broad page queries and uncached public SSR are secondary issues.

6. **What caused the merchandise subrequest error?**  
   The action made approximately 62 shared context calls before its one product insert, exceeding Cloudflare Free's 50 external subrequests. It was not caused by image upload, variant loops, stock insertion, redirects, or slow SQL.

7. **Can the system reasonably remain on free tiers at current expected usage?**  
   Yes, after correction. Database, Auth, Storage, Edge Function, R2, bundle, and build usage have substantial observed headroom. Exact Cloudflare requests/CPU and Supabase egress were unavailable and must be monitored. Upgrade for sustained 70–80% usage, reliability/backups/SLA, or business requirements—not to preserve the current fan-out.

8. **What should be implemented first after approval?**  
   First establish authenticated timing in preview, revoke unsafe database function grants, then replace per-permission fan-out with one `get_portal_context` call and one action-specific permission decision. This is the smallest change that fixes both the runtime failure and the dominant portal latency while preserving RLS and server-side authorisation.

