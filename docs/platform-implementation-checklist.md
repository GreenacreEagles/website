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
- [x] Add Supabase server client for Cloudflare SSR routes.
- [x] Build signup, signin, signout, password reset, account, and portal entry flows.
- [x] Add server-side protected portal routes.
- [x] Add shared protected portal layout.
- [x] Ensure migration provisions new users as general users only.
- [x] Add rollback smoke test for profile provisioning and default role safety.

## Phase 3: Admin And Permissions

- [x] Build permission-aware admin layout.
- [x] Build user search and role assignment screens.
- [x] Move role assignment into Users and remove the separate role assignment admin route.
- [x] Prevent super-admin escalation except through protected workflow.
- [x] Deprecate role requests, remove request/review routes, and retain historical records.
- [x] Add audit log viewer.
- [x] Add role catalog and role assignment views.
- [x] Add season and team administration foundation.
- [x] Add rollback smoke checks for disabled role requests and role assignment security.
- [ ] Reconcile remote migration history for MCP-applied follow-up migrations after Supabase CLI privileges are restored.
- [ ] Bootstrap the first approved super administrator.

## Phase 4: Club Operations

- [x] Build seasons and teams administration foundation.
- [x] Remove fixtures from member/admin navigation while preserving fixture data internally.
- [x] Add private team posts, reactions and poll foundations with RLS.
- [x] Build family relationship invitations, member acceptance, admin family linking and player/team assignment controls.
- [x] Add guardian-visible family wallets/vouchers and child canteen order beneficiary selection.
- [x] Build full squads, staff and match reports management.
- [x] Build family and guardian management foundation.
- [x] Build volunteer shifts and assignments.
- [ ] Build coaching resource library.

## Phase 5: Commerce

- [x] Build canteen catalogue management.
- [x] Build canteen customer ordering foundation with linked-child beneficiary support.
- [x] Build canteen operations queue.
- [x] Build secure voucher QR issuing, scanning, redemption, and reversal.
- [x] Build family voucher assignment audit trail and protected assignment RPC.
- [x] Build full wallet ledger operations and top-up/payment flow.
- [x] Build merchandise catalogue and order management.
- [x] Add payment-provider abstraction and webhook idempotency.

## Phase 6: Content And Communications

- [ ] Move public editable content into database-backed workflow where needed.
- [ ] Build announcements, news, sponsor and event publishing.
- [x] Absorb member notifications into the portal dashboard.
- [ ] Build notification preferences and communication outbox worker.

## Phase 7: Production Hardening

- [x] Add SQL smoke coverage for core role safety checks.
- [ ] Convert smoke coverage to automated pgTAP/local Supabase test flow.
- [ ] Add business-rule unit tests.
- [ ] Add end-to-end tests for critical journeys.
- [ ] Add Turnstile to public abuse-prone forms.
- [x] Configure Cloudflare Pages build/env vars for the current Pages domain.
- [ ] Confirm Cloudflare Pages `SESSION` KV and `IMAGES` bindings for the server-rendered Astro adapter.
- [ ] Configure custom domain.
- [ ] Document backup, recovery, and administrator runbooks.
