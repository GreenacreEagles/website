# Remote Snapshot After Platform Foundation

Date: 2026-07-21

Supabase project: `qzqezldtklimtupajvxf`

## Migration History

- `20260721130000_platform_foundation.sql`
- `20260721134500_revoke_public_rls_helper.sql`
- `20260721143000_foundation_advisor_fixes.sql`
- `20260721150000_foundation_performance_fixes.sql`

## Live Schema Summary

- Public application tables: 50
- Public views: 1
- Public tables with RLS disabled: 0
- Public policies: 143
- Seeded roles: 17
- Seeded permissions: 33
- Seeded role-permission links: 53
- Storage buckets: 0

## Advisor Status

- Security advisors: no lints.
- Performance advisors: only `unused_index` INFO notices remain. These are expected until the new schema has real query traffic.

## Smoke Test

Rollback-only auth provisioning test passed:

- New auth user creates a profile.
- New auth user receives `general_user`.
- User-editable metadata does not grant `super_admin`.
- New auth user cannot manage roles, canteen orders, or content.
