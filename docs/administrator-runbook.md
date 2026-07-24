# Administrator Runbook

This runbook is for trusted Greenacre Eagles platform administrators responsible for Supabase, Cloudflare Pages, production releases and incident response.

## Ownership

- Source of truth: GitHub repository.
- Hosting: Cloudflare Pages advanced mode serving `dist/client` with the generated `_worker.js` entry.
- Database and Auth: Supabase project `qzqezldtklimtupajvxf`.
- Production Pages domain: `https://website-4h5.pages.dev` until a custom domain is attached.
- Protected club administration starts at `/admin/`.

Only trusted technical administrators should hold Cloudflare, Supabase owner, GitHub maintainer or service-role access. Club role assignment inside the app is separate from infrastructure access.

## Routine Release Checklist

Before deploying:

1. Confirm all required migrations have been applied in Supabase.
2. Run `npm run typecheck`.
3. Run `npm run build`.
4. Run `npm run test:db` when local Supabase is running.
5. Review `git diff --stat` and make sure no secrets or generated `dist/` files are included.
6. Confirm Cloudflare environment variables and bindings are present for preview and production.
7. Deploy through Cloudflare Pages or `npm run deploy:worker`.
8. Smoke-test public, portal, admin and API routes.

Minimum route smoke test:

- `/`
- `/login/`
- `/news/`
- `/sponsors/`
- `/portal/`
- `/admin/`
- `/api/webhooks/payments/` with an invalid secret should return unauthorised JSON, not crash.
- `/api/workers/communication-outbox/` with an invalid secret should return unauthorised JSON, not crash.

## Supabase Migrations

All schema changes must be represented by files in `supabase/migrations/`.

Safe migration process:

1. Create migrations with `supabase migration new descriptive_name`.
2. Keep migrations forward-only. Do not edit a migration after it has been applied remotely.
3. Prefer additive changes and explicit data backfills.
4. Enable RLS on every exposed public table.
5. Add explicit `GRANT` statements for tables/functions that must be reachable through the Supabase Data API.
6. Revoke `PUBLIC` execution from privileged functions and grant only the intended roles.
7. Run Supabase security and performance advisors after applying production migrations.
8. Regenerate `src/types/database.types.ts` after schema changes.

If a migration fails:

1. Stop and capture the exact error.
2. Do not mark the migration as applied manually.
3. If the migration partially changed the database, create a forward fix migration.
4. Do not drop financial, audit, voucher, wallet, payment, role or user history to recover quickly.

Known follow-up: some early follow-up migrations were applied through Supabase SQL tooling while CLI migration-history permissions were unavailable. Reconcile remote migration history before relying on automated pushes as the only source of truth.

## Supabase Backup

Before major releases:

1. Take a Supabase Dashboard backup or export.
2. Record the timestamp, migration version and release commit.
3. Export schema separately when possible.
4. Confirm the backup is visible in the Supabase project before applying migrations.

Suggested backup record:

```text
Date:
Operator:
Supabase project:
Git commit:
Latest migration:
Backup type:
Backup location:
Advisor result:
Notes:
```

For high-risk releases involving payments, wallets, vouchers or role permissions, pause admin data-entry work during migration apply and verification.

## Supabase Recovery

Recovery must preserve auditability.

If bad application code was deployed:

1. Roll back Cloudflare to the previous successful deployment.
2. Leave database records intact unless a forward correction is required.
3. Review `audit_logs`, payment records, wallet ledger entries and webhook events for affected actions.

If bad data was written:

1. Identify affected rows with read-only queries first.
2. Prefer existing reversal RPCs, status transitions or administrative correction workflows.
3. For wallet, voucher, order, payment and role mistakes, use forward corrective records rather than deleting history.
4. Record the incident and correction reason in the admin audit trail where possible.

If a database restore is required:

1. Restrict admin access during the restore window.
2. Restore from the selected Supabase backup.
3. Reapply only verified migrations after the restore point.
4. Regenerate database types if the restored schema differs from source.
5. Smoke-test auth, portal dashboard, admin dashboard, wallet, canteen, merchandise, events and public publishing before reopening.

## Cloudflare Pages

Required production settings:

- Build command: `npm run build`
- Output directory: `dist/client`
- Node version: `22`
- Compatibility flag: `nodejs_compat`
- Pages Functions enabled by generated `dist/client/_worker.js/index.js`

Required bindings:

- `SESSION`: Workers KV binding for Astro sessions.
- `IMAGES`: Cloudflare Images binding when image upload/delivery features are enabled.

Required variables and secrets:

- `SITE_URL`
- `PUBLIC_SUPABASE_URL`
- `PUBLIC_SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `PAYMENT_WEBHOOK_SECRET`
- `COMMUNICATION_WORKER_SECRET`
- `PUBLIC_TURNSTILE_SITE_KEY`
- `TURNSTILE_SECRET_KEY`
- `NODE_VERSION=22`

Never expose `SUPABASE_SERVICE_ROLE_KEY`, webhook secrets or worker secrets in public variables.

## Cloudflare Rollback

If a deploy is unhealthy:

1. Use Cloudflare Pages deployment history to roll back to the previous known-good deployment.
2. Confirm `/login/`, `/portal/`, `/admin/`, `/news/` and `/api/` routes respond.
3. Check Cloudflare Function logs for runtime errors.
4. If the bad release included database migrations, do not roll back the database by dropping objects. Create a forward migration or restore from backup only after impact review.

## Secret Rotation

Rotate secrets when a maintainer leaves, a token is exposed, logs reveal sensitive material, or a provider webhook is reconfigured.

Rotation order:

1. Create the new secret in the provider.
2. Add/update the Cloudflare secret.
3. Deploy or redeploy if needed.
4. Test the affected endpoint.
5. Disable the old secret.
6. Record the rotation date and operator.

For payment and communication webhooks, expect a short overlap window where both provider dashboards and Cloudflare settings must be checked carefully.

## Super Administrator Access

The first super administrator must be bootstrapped manually with the trusted SQL process in `docs/super-admin-bootstrap.md`.

After bootstrap:

- Use `/admin/users/[id]/` for normal role assignment.
- Do not grant `super_administrator` to general administrators.
- Do not remove the final active super administrator.
- Review role assignment history after any emergency access change.

## Payment And Wallet Incidents

Financial records use immutable ledger and history tables. The browser must never directly set balances, payment status or voucher value.

If a payment webhook is replayed or duplicated:

1. Check `payment_webhook_events`.
2. Confirm `process_payment_webhook` idempotency result.
3. Check `payments` and related wallet ledger entries.

If an incorrect wallet credit/debit occurs:

1. Do not edit ledger rows in place.
2. Use the wallet reversal or controlled adjustment workflow.
3. Record a clear reason.
4. Notify affected members through the notification/outbox system if needed.

## Communication Outbox

Email and SMS jobs are provider-neutral. A trusted scheduled worker should:

1. Call `/api/workers/communication-outbox/` with `COMMUNICATION_WORKER_SECRET` and `action: "claim"`.
2. Send each claimed job through the selected provider.
3. Mark each job `complete` with the external provider message ID, or `fail` with a retry delay and failure reason.

Do not make wallet, payment, voucher, role or order transactions depend on successful external email/SMS delivery.

## Turnstile

Public sign in, signup and password reset forms render Turnstile when `PUBLIC_TURNSTILE_SITE_KEY` exists. Server validation is enforced when `TURNSTILE_SECRET_KEY` exists.

If users report they cannot submit auth forms:

1. Confirm both Turnstile keys are configured for the active hostname.
2. Check Cloudflare Pages logs for Siteverify errors.
3. Confirm the user's browser can reach Cloudflare Turnstile.
4. Temporarily remove `TURNSTILE_SECRET_KEY` only as a deliberate incident response action.

## Advisor And Audit Cadence

Monthly:

- Run Supabase security advisors.
- Run Supabase performance advisors.
- Review unused indexes only after real production traffic exists.
- Review Cloudflare Function errors.
- Review failed communication outbox jobs.
- Review payment webhook failures and unmatched provider events.
- Review recent super administrator and role assignment activity.

After major releases:

- Run advisors again.
- Confirm no new public `SECURITY DEFINER` functions are exposed unintentionally.
- Confirm new public tables have RLS and explicit grants.
- Confirm protected routes still require authenticated sessions.

## Incident Notes Template

```text
Incident:
Started:
Detected by:
Impact:
Systems affected:
Immediate action:
Data correction:
Deployment rollback:
Notifications sent:
Root cause:
Follow-up tasks:
Closed:
```
