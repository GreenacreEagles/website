# Platform Foundation Preflight

Date: 2026-07-21

## Verdict

Applied and verified.

The target Supabase project is confirmed, the local CLI is linked, and the foundation migrations have been applied to the remote project. Follow-up advisor fixes were also applied after the first remote pass.

## Supabase Project Identity

- Project ref: `qzqezldtklimtupajvxf`
- Project name: `GreenacreEagles's Project`
- Project URL: `https://qzqezldtklimtupajvxf.supabase.co`
- Database host: `db.qzqezldtklimtupajvxf.supabase.co`
- Region: `ap-southeast-2`
- Status during this pass: `ACTIVE_HEALTHY`
- Auth users: `0`

## CLI Status

- Supabase CLI version: `2.105.0`
- `supabase link --help`: inspected
- `supabase db push --help`: inspected
- `supabase migration list --help`: inspected
- Link status: linked to `qzqezldtklimtupajvxf`

## Local Migration List

- `supabase/migrations/20260721130000_platform_foundation.sql`
- `supabase/migrations/20260721134500_revoke_public_rls_helper.sql`
- `supabase/migrations/20260721143000_foundation_advisor_fixes.sql`
- `supabase/migrations/20260721150000_foundation_performance_fixes.sql`

## Remote Migration List

Remote CLI migration history matches the local migration list.

## Schema Drift Found

The live database now has the foundation application schema.

Current live summary:

- 50 public application tables
- 1 public view
- 0 public tables with RLS disabled
- 143 public RLS policies
- 17 seeded platform roles
- 33 seeded permissions
- 53 seeded role-permission links
- 0 storage buckets

Safe metadata snapshot: `supabase/remote-snapshots/20260721-pre-foundation.md`

## Destructive Operations Found

No destructive table, column, or data operations were found in the foundation migration.

One trigger statement is intentionally defensive:

```sql
drop trigger if exists on_auth_user_created on auth.users;
```

This replaces only the auth-user provisioning trigger name used by this platform. The current live schema has no trigger with that name.

## Existing-Data Impact

Current auth user count is `0`, so no live user records require backfill.

The migration now includes safe backfill for environments where auth users already exist:

- Creates missing `profiles` rows from `auth.users`.
- Assigns only `general_user`.
- Does not assign operational roles from user-editable metadata.

## Data Backfills Required

No manual data backfill is required for the current remote project because no users or application tables exist.

## Explicit API Grants Required

Required and now included in the migration:

- `grant usage on schema public to anon, authenticated`
- Public `select` grants for public-readable tables
- Authenticated table grants across public tables, with RLS enforcing row access
- Explicit RPC grants for intended functions only
- No `anon` grant for `public.has_permission`

## RLS Review

The migration enables RLS on every public application table.

Policies were reviewed for:

- No broad `TO authenticated` policy without row or permission predicates.
- Update policies include `WITH CHECK` where mutable access is allowed.
- Sensitive records such as role assignments, audit logs, vouchers, wallet ledgers, match reports, and medical/support notes are restricted by ownership, relationship, team scope, or permission checks.

Known follow-up for the testing phase: add database-level tests for all role, team-scope, family-scope, and voucher redemption policies before production use.

## Function Security Review

Changes made during this pass:

- Public RPC wrappers changed to `SECURITY INVOKER`.
- Privileged voucher operations remain in non-exposed `app_private`.
- `public.has_permission` changed to `SECURITY INVOKER`.
- Super-admin assignment is restricted by `app_private.can_assign_role()`.
- `app_private.bootstrap_super_admin()` is not granted to `anon` or `authenticated`.
- Existing `public.rls_auto_enable()` hardening is represented in `20260721134500_revoke_public_rls_helper.sql`.

No function uses `raw_user_meta_data` for authorization.

## Storage Impact

No storage buckets are created by this migration.

Storage bucket strategy remains a follow-up task before private media, coaching documents, registration files, or protected attachments are uploaded.

## Estimated Objects To Be Created

Approximate foundation objects:

- 50+ public tables/views across profiles, roles, teams, canteen, vouchers, wallets, merchandise, events, volunteers, coaching resources, content, notifications, audit, and files.
- `app_private` schema.
- Permission-checking, provisioning, audit, voucher redemption, wallet, and bootstrap functions.
- RLS policies for all public application tables.
- Standard roles and permissions.
- Explicit grants for Data API access.

## Dry-Run And Apply Result

Dry runs passed before remote apply.

Applied migrations:

- `20260721130000_platform_foundation.sql`
- `20260721134500_revoke_public_rls_helper.sql`
- `20260721143000_foundation_advisor_fixes.sql`
- `20260721150000_foundation_performance_fixes.sql`

Post-apply Supabase security advisors return no lints.

Post-apply Supabase performance advisors now report only `unused_index` INFO notices. Those are expected on a fresh empty schema and should be reviewed after real portal traffic instead of removed immediately.

## Rollback Or Recovery Approach

Before apply:

1. Confirm project identity.
2. Confirm migration history.
3. Take a Supabase dashboard backup or schema-only dump.
4. Run `supabase db push --linked --dry-run`.

If apply fails before completion, stop and inspect the error. Do not manually mark the migration applied unless the exact migration contents are proven to exist remotely.

If apply succeeds but a serious issue is found, create a forward migration to correct the issue. Do not drop financial, audit, redemption, or user history.

## Smoke Test Result

A rollback-only database smoke test created a temporary auth user and confirmed:

- Profile provisioning trigger creates `public.profiles`.
- New users receive only the `general_user` role.
- User-editable metadata does not grant `super_admin`.
- Default users cannot manage roles, canteen orders, or content.

## Final Preflight Result

The foundation is applied and ready for the next build phase: role-aware admin screens, real portal workflows, storage buckets, and production content/admin operations.
