# Backup and Recovery Runbook

This runbook covers backup, restore, and continuity for the Greenacre Eagles FC platform: Supabase Postgres/Auth, database RLS policies/functions, Cloudflare R2 objects, and Pages/repository configuration.

It complements `docs/administrator-runbook.md` (release process) and `docs/production-readiness-audit-20260729.md` (finding C1). Read both before running a real restore.

**Scope note:** the club currently accepts payment at the club only (`PAYMENT_PROVIDER=manual`). There is no live payment gateway to reconcile during a restore, but wallet ledgers, vouchers, canteen/merchandise orders, and WWCC compliance records are still real member data and must be recoverable.

## 1. Principles

1. **Never commit production data or secrets to Git.** No database dumps, `.env` files, service-role keys, R2 credentials, or WWCC documents may ever be added to this repository, an issue, a commit message, or a chat transcript. All backup artifacts stay outside version control — see [§7 Storage and retention](#7-storage-and-retention).
2. **Backups must be tested, not assumed.** An export that has never been restored is not a backup.
3. **Schema history lives in `supabase/migrations/`.** Migrations are forward-only (see `docs/administrator-runbook.md`). This runbook backs up the *deployed* schema/data state, not just migration files, because remote migration history has known drift (`docs/supabase-migration-reconciliation-20260729.md`).
4. **Least privilege.** Only the technical owner holds export/restore credentials. Restore into production requires a second person's authorization (§2).
5. **Encrypt anything that leaves Supabase/Cloudflare.** Logical dumps and R2 inventories contain member PII, wallet balances, and compliance data and must be encrypted at rest wherever they are stored.

## 2. Roles and authorization

| Role | Responsibility |
|---|---|
| **Technical owner** (named infrastructure admin) | Executes backups, verifies integrity, executes restores, holds/rotates credentials, runs quarterly restore drills. |
| **Club president or secretary** | Must explicitly authorize any restore into the **production** Supabase project or production R2 buckets before it happens. A restore into an isolated/staging project for testing does not require this authorization. |
| **Privacy officer / compliance lead** (may be the same person as president/secretary) | Verifies that any restore involving WWCC or member-compliance data is handled consistent with the club's privacy obligations, and that no compliance data left the approved encrypted storage location. |

**Rule:** the technical owner must never restore production data or production secrets without recorded sign-off from the president or secretary, except when actively stopping ongoing data loss (e.g. a destructive query in progress). Even then, notify the president/secretary as soon as safely possible and log the action per §8.

## 3. What must be backed up

| Item | Why | Source |
|---|---|---|
| Full logical data + schema dump | Recover all tables: identity, wallets/ledger, orders, WWCC, audit logs | Supabase Postgres (`supabase db dump` / `pg_dump`) |
| Schema-only dump (DDL) | Fast diff against `supabase/migrations/`, disaster-recovery schema rebuild without restoring live data | Supabase Postgres, schema-only |
| RLS policies, functions (RPCs), triggers, grants | These enforce every authorization boundary in the app; losing them silently reopens access control gaps | Included in schema dump; also exported individually for review (§5.2) |
| `auth.users` / Supabase Auth config | Login identities, email confirmation state | Supabase Auth export (dashboard) or `auth` schema dump where plan allows |
| R2 object inventory (both buckets) | WWCC private documents and public media are **not** covered by any Postgres backup | Cloudflare R2 S3 API listing (`scripts/backup/export-r2-inventory.mjs`) |
| R2 object copies (WWCC bucket, at minimum) | Object bytes themselves, not just keys/metadata | R2-to-R2 replication, `rclone`, or scheduled object copy to a second bucket/account |
| Pages/Worker configuration | `wrangler.jsonc`, environment variable *names* (not secret values), bindings | Already versioned in Git; confirm it matches the live Pages project each release |
| Secrets inventory (names + rotation date only, never values) | Ability to reprovision Cloudflare Pages secrets after a full rebuild | Manually maintained list, stored in the club's password manager, not Git |
| Migration reconciliation state | Understanding of what schema is actually live | `docs/supabase-migration-reconciliation-20260729.md` plus the schema dump diff |

## 4. Supabase plan decision: Pro vs. self-managed dumps

As of the last audit, the Supabase organization is on the **Free** plan, which has **no managed automatic backups and no point-in-time recovery (PITR)**. Pick one of the two paths below before broad member launch. Re-verify current Supabase plan documentation before deciding, since plan features change.

### Option A — Upgrade to Supabase Pro (recommended if budget allows)

- Adds automatic **daily backups** retained for 7 days out of the box, with optional paid PITR add-ons for tighter RPO.
- Removes the project-inactivity pause risk that applies to Free projects.
- Still export logical dumps periodically (§5) and copy them off-Supabase — Pro's backups live inside Supabase and do not protect against loss of the Supabase account/organization itself, and they do not back up R2 at all.
- Action: in the Supabase dashboard, go to **Settings → Billing** and upgrade the organization plan, then confirm **Database → Backups** shows scheduled daily backups.

### Option B — Encrypted logical dumps to independent storage (required if staying on Free)

- Schedule a recurring **schema + data dump** using `supabase db dump` or `pg_dump` (see `scripts/backup/export-schema.sh` / `.ps1` for schema-only; extend the same connection string for a full data dump).
- Encrypt the dump immediately after export (`age` or `gpg`), before it leaves the machine running the export.
- Upload the encrypted file to storage **independent of both Supabase and the primary Cloudflare account** — for example a second cloud provider's object storage, or a password-manager-attached encrypted drive for a very small club. The goal is that a single compromised or suspended account cannot destroy both the production system and its backups.
- Because this is a manual/scripted job rather than a managed platform feature, someone (the technical owner) must actually run it. Put a recurring calendar reminder or a scheduled task in place (Windows Task Scheduler, cron on a small VM, or a GitHub Actions workflow using a stored, encrypted, non-production connection string) — do not rely on memory alone.

**Either way**, R2 objects are never covered by a Supabase backup. R2 inventory/object copies (§5.3) are required regardless of which option is chosen.

## 5. Backup procedures

All commands are documented in `scripts/backup/README.md` with exact invocations. This section explains what each does and why.

### 5.1 Full data + schema dump

Use `supabase db dump` (preferred, handles Supabase-specific roles/extensions correctly) or `pg_dump` directly against the Supabase connection string from **Settings → Database → Connection string** (use the *pooler* connection string only for application traffic, not for `pg_dump`; use the direct connection for dumps).

```bash
supabase db dump --db-url "$SUPABASE_DB_URL" -f backups/local/full-$(date +%Y%m%dT%H%M%S).sql
```

On Windows PowerShell:

```powershell
supabase db dump --db-url $env:SUPABASE_DB_URL -f "backups/local/full-$(Get-Date -Format yyyyMMddTHHmmss).sql"
```

Never type the connection string directly into a shared terminal, script, or commit — export `SUPABASE_DB_URL` as an environment variable for the session only, from a value stored in the club's password manager.

### 5.2 Schema-only dump (RLS, functions, policies, grants)

Run `scripts/backup/export-schema.sh` (macOS/Linux) or `scripts/backup/export-schema.ps1` (Windows). This produces schema-only DDL — table definitions, RLS policies, functions/RPCs, triggers, and grants — with no row data, safe to review by more people than the full dump because it contains no member PII.

Use this after every production migration to diff against `supabase/migrations/` and confirm what's actually live (see the migration reconciliation note in §1).

### 5.3 R2 object inventory and copies

Cloudflare R2 has no built-in backup product as of the last review; treat it the same as any S3-compatible bucket.

1. **Inventory (required, low cost):** run `node scripts/backup/export-r2-inventory.mjs` to list every object key, size, and last-modified timestamp in both `PUBLIC_MEDIA_BUCKET` and `PRIVATE_MEDIA_BUCKET` via the R2 S3-compatible API. This gives you a manifest to detect missing/deleted objects and to drive a restore-verification pass. It does **not** copy the object bytes.
2. **Object copies (required for the private/WWCC bucket, recommended for public media):** use one of:
   - Cloudflare **R2 bucket-to-bucket copy** via `rclone` (`rclone sync r2:greenacre-eagles-private-media r2-backup:greenacre-eagles-private-media-backup`) configured with the S3-compatible endpoint and credentials, ideally to a **separate R2 account or separate cloud provider**.
   - A second Cloudflare account with its own R2 bucket, so a single compromised Cloudflare account cannot destroy both copies.
3. Enable R2 **object lifecycle / versioning** where available for the private bucket to protect against accidental overwrite/delete between scheduled copies (check current Cloudflare R2 documentation for the exact feature name and availability, as this evolves).

### 5.4 Pages/Worker configuration and secrets inventory

- `wrangler.jsonc` is already in Git — confirm it matches the live Cloudflare Pages project settings after every change (bindings, KV namespace, R2 bucket names).
- Maintain a secrets *inventory* (name, purpose, last rotated date — never the value) outside Git, in the club's password manager. See `.env.example` for the full list of variable names currently required.
- After any Cloudflare Pages environment variable change, update the inventory the same day.

### 5.5 Integrity diagnostics as part of a backup cycle

Run the read-only diagnostics in `scripts/backup/run-integrity-diagnostics.sql` (or `scripts/diagnostics/run-integrity-checks.mjs`) **before** trusting a backup as "clean." These call the existing `diagnose_data_integrity`, `diagnose_wallet_reconciliation`, and `diagnose_r2_file_orphans` database functions and never mutate data. If they report mismatches, note them alongside the backup record — restoring a backup with known unreconciled wallet mismatches is still useful, but the mismatch should not be mistaken for restore corruption later.

Note: these functions authorize themselves against a real signed-in account (`auth.uid()` plus a permission check), not a raw database connection — see `scripts/backup/README.md` for exactly how each script satisfies that.

## 6. Restore validation

**Never restore directly into production to "test" a backup.** Always restore into an isolated environment first.

### 6.1 Standard restore drill (quarterly, or before a major schema change)

1. Technical owner creates a new, throwaway Supabase project (or a local Supabase instance via the Supabase CLI: `supabase start`).
2. Restore the most recent full dump into the isolated project:
   ```bash
   psql "$ISOLATED_DB_URL" -f backups/local/full-<timestamp>.sql
   ```
3. Run `scripts/backup/run-integrity-diagnostics.sql` against the isolated project. Confirm it returns the same known-issue baseline as production (no new mismatches introduced by the restore itself).
4. Spot-check row counts for key tables (`profiles`, `wallet_accounts`, `wallet_ledger_entries`, `wwcc_submissions`, `canteen_orders`) against the source project at dump time.
5. Confirm RLS is enabled on every table restored (`select relname from pg_class join pg_namespace on ... where relrowsecurity = false` for `public` schema tables — should return none unexpected) and that `anon`/`authenticated` grants match expectations.
6. For an R2 restore drill, copy a small sample of objects from the backup bucket/location into a throwaway R2 bucket and confirm they open correctly and match the inventory manifest's size/hash.
7. Record the result using the template in §8. Destroy the isolated project/bucket afterward unless it is being reused for the next drill.

### 6.2 Real incident restore (production)

1. Stop further writes if the incident is ongoing (maintenance mode, disable the affected endpoint, or pause the Cloudflare Pages deployment).
2. Technical owner identifies the most recent good backup and confirms its timestamp against the incident window.
3. **Obtain authorization** from the president or secretary before restoring into production (§2), documenting the decision (§8) — unless actively stopping ongoing irreversible loss, per the exception in §2.
4. Restore into an isolated project first if there is any time budget to do so, to catch dump corruption before touching production.
5. Restore into production following the Supabase-provided restore path for the chosen plan (Pro dashboard restore, or `psql`/`supabase db dump` reversed into the production connection for Option B).
6. Re-run `scripts/backup/run-integrity-diagnostics.sql` against production immediately after restore.
7. Reconcile R2 objects against the most recent inventory manifest; re-copy any objects that are missing from production but present in the backup copy.
8. Smoke-test per `docs/administrator-runbook.md` §"Minimum route smoke test."
9. Record the incident and restore in the audit log and in §8 of this runbook.

## 7. Storage and retention

| Artifact | Where it lives | Encryption | Retention |
|---|---|---|---|
| Full data + schema dumps | Independent storage outside Supabase/Cloudflare (or Supabase Pro managed backups) | Encrypted at rest (age/gpg for manual dumps; provider-managed for Pro) | 7 daily, 4 weekly, 3 monthly (adjust to what the club can realistically operate) |
| Schema-only dumps | Same independent storage; may also be reviewed locally under `backups/local/` (gitignored) | Not strictly required (no PII) but recommended | Keep alongside each full dump plus one per production migration |
| R2 object copies | Separate R2 account/bucket or separate cloud provider | Provider-managed at-rest encryption at minimum; consider client-side encryption for WWCC objects | Mirror of live bucket, plus 30 days of prior-version retention if versioning is enabled |
| R2 inventory manifests | `backups/local/` locally (gitignored) and copied to the same independent storage as dumps | Not required (no file contents, only keys/sizes) | 90 days |
| Local working copies (`backups/local/`) | Developer/operator machine only | Disk encryption (BitLocker/FileVault) recommended | Delete after successful upload to independent storage; never leave stale dumps on a laptop |

`backups/local/` is gitignored (§ .gitignore update) specifically so that no one accidentally commits a dump. Treat anything under it as sensitive even though Git will never see it.

## 8. Credentials handling

- `SUPABASE_DB_URL` (direct Postgres connection string) and R2 S3 credentials (`CLOUDFLARE_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`) must only exist as:
  - entries in the club's password manager, and
  - short-lived environment variables set in the technical owner's own shell session for the duration of a backup/restore.
- Never paste these into chat, tickets, commit messages, or a shared document.
- Rotate R2 S3 credentials and the Supabase database password at least yearly, and immediately after any suspected compromise or personnel change.
- The technical owner should be the only person with standing access to production backup/restore credentials. If a second person needs emergency access (e.g. technical owner unavailable during an incident), store a sealed/rotated emergency credential per the club's own physical security process — this is an organizational decision for the president/secretary, not an engineering one.

## 9. RPO / RTO targets

These are targets for a small-club operation, not contractual guarantees. Re-evaluate if the club grows materially or takes on online payments.

| Data | RPO (max acceptable data loss) | RTO (max acceptable downtime to restore) | Basis |
|---|---:|---:|---|
| Auth / Postgres (profiles, wallets, orders, WWCC, audit) | 24 hours on Free-plan manual dumps; 15 minutes if Supabase Pro PITR add-on is purchased | 4 hours | Daily encrypted dump or Pro backup; quarterly isolated restore drill |
| R2 private (WWCC) files | 24 hours | 8 hours | Encrypted second copy/version manifest; quarterly sample restore |
| R2 public media | 24 hours | 24 hours | Second bucket/off-site copy; lower urgency, publicly re-obtainable in most cases |
| Pages/Worker environment and config | Every change (config is version-controlled or inventoried immediately) | 2 hours | `wrangler.jsonc` in Git plus secrets inventory |
| Admin/infrastructure access itself | Immediate (no data loss window, an access-control incident) | 2 hours | Two known super admins, this runbook, password-manager-based credential rotation |

If the club later enables online payments (`PAYMENT_PROVIDER` other than `manual`), revisit RPO/RTO for payment/webhook event tables specifically, since a provider may expect faster reconciliation.

## 10. Record-keeping template

Keep one entry per backup run and per restore drill/incident. Store this log outside Git (e.g. a shared document), since it may reference internal timestamps and incident details.

```text
Date/time (UTC):
Type: [scheduled dump | pre-migration schema dump | R2 inventory | restore drill | incident restore]
Operator (technical owner):
Authorized by (president/secretary, restores only):
Supabase project:
Migration version at time of backup:
Artifact location (independent storage, not the file itself):
Integrity diagnostics result (attach summary counts only, no PII):
Outcome / issues:
```

## 11. Related documents

- `docs/administrator-runbook.md` — release process and existing Supabase backup checklist.
- `docs/production-readiness-audit-20260729.md` — finding C1 (no production-grade recovery) and the backup/RPO/RTO table this runbook expands on.
- `docs/supabase-migration-reconciliation-20260729.md` — why schema dumps must be diffed against actual migration history rather than assumed correct.
- `docs/monitoring-and-alerting-runbook.md` — alerting that should catch problems before a restore is ever needed.
- `scripts/backup/README.md` — exact commands for every procedure referenced above.
