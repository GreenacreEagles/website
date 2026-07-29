#!/usr/bin/env bash
# Schema-only export: tables, RLS policies, functions/RPCs, triggers, grants.
# No row data is exported by this script. See docs/backup-and-recovery-runbook.md
# for the full data-dump command (deliberately not scripted, so a full export
# always requires an explicit, reviewed command).
#
# Requires SUPABASE_DB_URL to be set to a *direct* (non-pooler) Postgres
# connection string. Never hardcode credentials in this file.
#
# Usage:
#   export SUPABASE_DB_URL="postgresql://postgres:<password>@db.<project-ref>.supabase.co:5432/postgres"
#   ./scripts/backup/export-schema.sh

set -euo pipefail

if [[ -z "${SUPABASE_DB_URL:-}" ]]; then
  echo "error: SUPABASE_DB_URL is not set. Export it from a value in the password manager first." >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${BACKUP_OUTPUT_DIR:-$repo_root/backups/local}"
mkdir -p "$output_dir"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
output_file="$output_dir/schema-$timestamp.sql"

echo "Exporting schema-only dump to: $output_file"

if command -v supabase >/dev/null 2>&1; then
  # Preferred: Supabase CLI understands Supabase-managed roles/extensions.
  supabase db dump --db-url "$SUPABASE_DB_URL" --schema-only -f "$output_file"
elif command -v pg_dump >/dev/null 2>&1; then
  echo "warning: Supabase CLI not found, falling back to pg_dump directly." >&2
  pg_dump "$SUPABASE_DB_URL" \
    --schema-only \
    --no-owner \
    --no-privileges=false \
    --schema=public \
    --schema=app_private \
    --file="$output_file"
else
  echo "error: neither the Supabase CLI nor pg_dump was found on PATH." >&2
  echo "Install one of: https://supabase.com/docs/guides/cli or PostgreSQL client tools." >&2
  exit 1
fi

echo "Done. Remember this file may contain internal schema/security details — keep it out of Git (it already is, via .gitignore) and out of chat/tickets."
