# Platform Implementation Checklist

## Phase 1: Foundation

- [x] Audit repository, Supabase project, and Cloudflare Pages configuration.
- [x] Add Supabase project config.
- [x] Add first migration for profiles, roles, permissions, teams, canteen, vouchers, wallet ledger, merchandise, events, volunteers, content, notifications, and audit logging.
- [x] Add environment variable reference.
- [x] Harden pre-existing `public.rls_auto_enable()` live and add matching migration.
- [x] Review foundation migration and patch pre-apply issues.
- [x] Capture safe remote schema snapshot.
- [x] Create platform foundation preflight report.
- [x] Link local Supabase CLI to project.
- [x] Run `supabase db push --linked --dry-run`.
- [x] Apply migrations to Supabase production project.
- [x] Run Supabase advisors after migration. Security advisors pass; performance has only expected unused-index notices on the fresh schema.
- [x] Generate TypeScript database types.
- [x] Document secure super-admin bootstrap process.

## Phase 2: Authentication And Portal Shell

- [x] Install Supabase client dependencies.
- [x] Add Supabase browser client.
- [x] Build signup, signin, signout, password reset, account, and portal entry flows.
- [x] Add client-side protected portal/admin entry routes.
- [x] Ensure migration provisions new users as general users only.
- [x] Add rollback smoke test for profile provisioning and default role safety.

## Phase 3: Admin And Permissions

- [ ] Build permission-aware admin layout.
- [ ] Build user search and role assignment screens.
- [ ] Prevent super-admin escalation except through protected workflow.
- [ ] Add role request review.
- [ ] Add audit log viewer.

## Phase 4: Club Operations

- [ ] Build seasons, teams, squads, staff, fixtures, and match reports.
- [ ] Build family and guardian management.
- [ ] Build volunteer shifts and assignments.
- [ ] Build coaching resource library.

## Phase 5: Commerce

- [ ] Build canteen catalogue management.
- [ ] Build canteen customer ordering.
- [ ] Build canteen operations queue.
- [ ] Build secure voucher QR issuing, scanning, redemption, and reversal.
- [ ] Build wallet ledger operations.
- [ ] Build merchandise catalogue and order management.
- [ ] Add payment-provider abstraction and webhook idempotency.

## Phase 6: Content And Communications

- [ ] Move public editable content into database-backed workflow where needed.
- [ ] Build announcements, news, sponsor and event publishing.
- [ ] Build notification preferences and communication outbox worker.

## Phase 7: Production Hardening

- [ ] Add automated RLS tests.
- [ ] Add business-rule unit tests.
- [ ] Add end-to-end tests for critical journeys.
- [ ] Add Turnstile to public abuse-prone forms.
- [x] Configure Cloudflare Pages build/env vars for the current Pages domain.
- [ ] Configure custom domain.
- [ ] Document backup, recovery, and administrator runbooks.
