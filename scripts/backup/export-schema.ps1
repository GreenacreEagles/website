# Schema-only export: tables, RLS policies, functions/RPCs, triggers, grants.
# No row data is exported by this script. See docs/backup-and-recovery-runbook.md
# for the full data-dump command (deliberately not scripted, so a full export
# always requires an explicit, reviewed command).
#
# Requires $env:SUPABASE_DB_URL to be set to a *direct* (non-pooler) Postgres
# connection string. Never hardcode credentials in this file.
#
# Usage:
#   $env:SUPABASE_DB_URL = "postgresql://postgres:<password>@db.<project-ref>.supabase.co:5432/postgres"
#   ./scripts/backup/export-schema.ps1

$ErrorActionPreference = "Stop"

if (-not $env:SUPABASE_DB_URL) {
    Write-Error "SUPABASE_DB_URL is not set. Export it from a value in the password manager first."
    exit 1
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$outputDir = if ($env:BACKUP_OUTPUT_DIR) { $env:BACKUP_OUTPUT_DIR } else { Join-Path $repoRoot "backups\local" }
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$outputFile = Join-Path $outputDir "schema-$timestamp.sql"

Write-Host "Exporting schema-only dump to: $outputFile"

$supabaseCli = Get-Command supabase -ErrorAction SilentlyContinue
$pgDump = Get-Command pg_dump -ErrorAction SilentlyContinue

if ($supabaseCli) {
    # Preferred: Supabase CLI understands Supabase-managed roles/extensions.
    & supabase db dump --db-url $env:SUPABASE_DB_URL --schema-only -f $outputFile
}
elseif ($pgDump) {
    Write-Warning "Supabase CLI not found, falling back to pg_dump directly."
    & pg_dump $env:SUPABASE_DB_URL `
        --schema-only `
        --no-owner `
        --schema=public `
        --schema=app_private `
        --file=$outputFile
}
else {
    Write-Error "Neither the Supabase CLI nor pg_dump was found on PATH. Install one of: https://supabase.com/docs/guides/cli or PostgreSQL client tools (e.g. via https://www.postgresql.org/download/windows/)."
    exit 1
}

Write-Host "Done. Remember this file may contain internal schema/security details -- keep it out of Git (it already is, via .gitignore) and out of chat/tickets."
