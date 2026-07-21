# Remote Schema Snapshot Before Foundation Migration

Captured: 2026-07-21

Project: `qzqezldtklimtupajvxf`  
Host: `db.qzqezldtklimtupajvxf.supabase.co`  
Project status: `ACTIVE_HEALTHY`

This snapshot intentionally contains schema metadata only. It does not contain secrets or user records.

## Migration History

The query against `supabase_migrations.schema_migrations` failed because the relation does not exist.

Interpretation: the linked migration-history table has not been created in this database, or Supabase CLI migration history has never been initialized for this project.

## Public Application Schema

- Public application tables: none found.
- Public RLS policies: none found.
- Public triggers: none found.
- Public table grants: none found.

## Existing Public Functions

| Schema | Function | Security |
| --- | --- | --- |
| `public` | `rls_auto_enable()` | `SECURITY DEFINER` |

The previous pass revoked `EXECUTE` on `public.rls_auto_enable()` from `anon`, `authenticated`, and `public`. Supabase advisors confirmed no remaining security lint after that live hardening.

## Storage

- Storage buckets: none found.

## Edge Functions

- Edge Functions: none found.

## Auth

- Auth users: `0`

## Built-In Schemas Present

Built-in Supabase schemas present include `auth`, `extensions`, `realtime`, `storage`, and `vault`.
