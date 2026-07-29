# Backup Scripts

Practical, safe scripts supporting `docs/backup-and-recovery-runbook.md`. Read that runbook first — this file only documents *how* to run each script, not the policy behind it.

All scripts write output under `backups/local/`, which is gitignored (see the repository root `.gitignore`). **Never move a backup artifact into a tracked path, and never commit anything from `backups/local/`.**

The repository is developed on Windows. Every script that needs a shell wrapper is provided as both a POSIX `.sh` script and a Windows PowerShell `.ps1` script; the underlying tool invocation (`supabase`, `pg_dump`, Node) is identical either way.

## Prerequisites

- [Supabase CLI](https://supabase.com/docs/guides/cli) installed and authenticated (`supabase login`), for `export-schema.*` and full data dumps.
- `psql`/`pg_dump` on your `PATH` if you prefer raw `pg_dump` over the Supabase CLI wrapper (the Supabase CLI bundles a compatible Postgres client, so a separate install usually isn't required).
- Node.js 20.19+ (already required by `package.json`) for `export-r2-inventory.mjs`.
- Credentials, sourced from the club's password manager and exported as environment variables **for the current shell session only** — never written into a script, `.env` committed to Git, or shared chat:
  - `SUPABASE_DB_URL` — direct (non-pooler) Postgres connection string, for schema/data dumps.
  - `CLOUDFLARE_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY` — R2 S3-compatible API credentials, for the inventory script.
  - `PUBLIC_SUPABASE_URL` (or `SUPABASE_URL`) and `SUPABASE_SERVICE_ROLE_KEY` — for `scripts/diagnostics/run-integrity-checks.mjs`.

## Scripts

### `export-schema.sh` / `export-schema.ps1`

Schema-only export (no row data): tables, RLS policies, functions/RPCs, triggers, and grants. Safe to review more broadly than a full data dump because it contains no member PII.

```bash
# macOS/Linux/WSL, from the repo root
export SUPABASE_DB_URL="postgresql://postgres:<password>@db.<project-ref>.supabase.co:5432/postgres"
./scripts/backup/export-schema.sh
```

```powershell
# Windows PowerShell, from the repo root
$env:SUPABASE_DB_URL = "postgresql://postgres:<password>@db.<project-ref>.supabase.co:5432/postgres"
./scripts/backup/export-schema.ps1
```

Output: `backups/local/schema-<UTC timestamp>.sql`.

The script prefers `supabase db dump --schema-only` when the Supabase CLI is available (handles Supabase-specific roles/extensions correctly) and falls back to `pg_dump --schema-only --no-owner --no-privileges=false` against `SUPABASE_DB_URL` otherwise. It does **not** perform a full data dump — see the runbook §5.1 for that command, which is intentionally not wrapped in a script here so that a full-data export always requires a deliberate, explicit command rather than a habitual script run.

### `export-r2-inventory.mjs`

Lists every object key, size, and last-modified timestamp in both R2 buckets (`PUBLIC_MEDIA_BUCKET` / `PRIVATE_MEDIA_BUCKET`, from `wrangler.jsonc`) via the R2 S3-compatible API. Uses only Node's built-in `crypto`/`https` modules to sign requests (AWS Signature Version 4) — no extra dependency is required.

This produces a **manifest of keys**, not object bytes. See `docs/backup-and-recovery-runbook.md` §5.3 for how to also copy the underlying objects (e.g. via `rclone`).

```bash
export CLOUDFLARE_ACCOUNT_ID="..."
export R2_ACCESS_KEY_ID="..."
export R2_SECRET_ACCESS_KEY="..."
node scripts/backup/export-r2-inventory.mjs
```

PowerShell:

```powershell
$env:CLOUDFLARE_ACCOUNT_ID = "..."
$env:R2_ACCESS_KEY_ID = "..."
$env:R2_SECRET_ACCESS_KEY = "..."
node scripts/backup/export-r2-inventory.mjs
```

Optional environment variables:

- `R2_PUBLIC_BUCKET_NAME` / `R2_PRIVATE_BUCKET_NAME` — override the default bucket names from `wrangler.jsonc`.
- `R2_INVENTORY_OUTPUT_DIR` — override the default `backups/local/` output directory.

Output: `backups/local/r2-inventory-<bucket>-<UTC timestamp>.json`, plus a `-summary.json` file with object counts and total bytes only (safe to paste into a status update).

### `run-integrity-diagnostics.sql`

Read-only SQL that calls the existing `diagnose_data_integrity()`, `diagnose_wallet_reconciliation()`, and `diagnose_r2_file_orphans()` database functions (defined in `supabase/migrations/20260730010001_production_hardening_diagnostics.sql`). None of these functions mutate data; the script wraps every call in a transaction that always ends with `ROLLBACK`.

These functions check `auth.uid()` and `app_private.has_permission(...)` internally, so a plain `psql` connection has no JWT context by default and every call will fail with `Not authorised` unless you simulate an authorized session first. The script does this for you via `set_config('request.jwt.claims', ...)` and `set local role authenticated` (the same technique Supabase's own RLS-testing documentation recommends) — you just need to pass the `auth.users.id` of an account that holds `users.manage` (and `wallet.adjust` for wallet reconciliation):

```bash
psql "$SUPABASE_DB_URL" -v admin_user_id="'00000000-0000-0000-0000-000000000000'" -f scripts/backup/run-integrity-diagnostics.sql
```

```powershell
psql $env:SUPABASE_DB_URL -v admin_user_id="'00000000-0000-0000-0000-000000000000'" -f scripts/backup/run-integrity-diagnostics.sql
```

Prefer `scripts/diagnostics/run-integrity-checks.mjs` for a routine scheduled job: it signs in through the normal Supabase Auth session path (no claim-simulation needed) and prints summary counts only by default (no raw PII) — see that script's header comment for full setup, including why a plain `SUPABASE_SERVICE_ROLE_KEY` alone is not sufficient for these specific RPCs.

## Safety rules for every script in this directory

1. Never hardcode a production connection string, service-role key, or R2 credential in any script — always read from environment variables.
2. Never write output outside `backups/local/` (or the path explicitly overridden via an env var pointing at another gitignored, non-tracked location).
3. Never print full credential values to stdout/stderr, even in error messages.
4. These scripts are read-only against the database (schema/data dump, diagnostics) or list-only against R2 (inventory). None of them delete, mutate, or restore anything — restore is a deliberate manual procedure documented in `docs/backup-and-recovery-runbook.md` §6, not a script, so that a restore into production always requires the explicit authorization step in that runbook.
