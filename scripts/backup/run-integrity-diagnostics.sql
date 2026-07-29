-- Read-only integrity diagnostics for backup/restore verification.
--
-- Calls the existing, read-only, permission-checked database functions defined in
-- supabase/migrations/20260730010001_production_hardening_diagnostics.sql:
--   - diagnose_data_integrity()
--   - diagnose_wallet_reconciliation(sample_limit integer default 100)
--   - diagnose_r2_file_orphans(sample_limit integer default 100)
--
-- None of these functions mutate data.
--
-- IMPORTANT -- these functions check `auth.uid()` and
-- `app_private.has_permission(...)` internally. A plain `psql`/superuser
-- connection (or the Supabase Studio SQL editor without extra setup) has no
-- JWT context, so `auth.uid()` evaluates to NULL and every call below will
-- raise "Not authorised" unless you first simulate an authorized session for
-- the duration of this transaction, as done below.
--
-- Replace :'admin_user_id' with the auth.users.id of a real account that
-- holds the 'users.manage' permission (and 'wallet.adjust' for wallet
-- reconciliation) -- e.g. a super administrator or a dedicated diagnostics
-- runner account. Never use a real member's personal account for a
-- scheduled/automated job; provision a dedicated low-privilege-as-possible
-- service account instead.
--
-- Usage:
--   psql "$SUPABASE_DB_URL" -v admin_user_id="'00000000-0000-0000-0000-000000000000'" -f scripts/backup/run-integrity-diagnostics.sql
--
-- Do not paste raw output containing member details outside a controlled,
-- access-restricted location. Prefer scripts/diagnostics/run-integrity-checks.mjs
-- for a routine scheduled job that prints summary counts only and signs in
-- through the normal Supabase Auth session path instead of simulating a claim.

\timing on

begin;

-- Simulate an authorized 'authenticated' session for this transaction only.
select set_config('request.jwt.claims', json_build_object('sub', :admin_user_id, 'role', 'authenticated')::text, true);
set local role authenticated;

select 'diagnose_data_integrity' as check_name, public.diagnose_data_integrity() as result;

select 'diagnose_wallet_reconciliation' as check_name, public.diagnose_wallet_reconciliation(200) as result;

select 'diagnose_r2_file_orphans' as check_name, public.diagnose_r2_file_orphans(200) as result;

rollback;
-- ROLLBACK is deliberate: these functions are read-only, and rolling back
-- also discards the simulated role/claims for this session so nothing about
-- the temporary impersonation persists.
