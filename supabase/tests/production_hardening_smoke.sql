begin;

create temp table smoke_results (check_name text, passed boolean, detail text);

-- ---------------------------------------------------------------------------
-- Functions introduced by the production hardening migrations must exist
-- with the exact signatures the application and Node test suite depend on.
-- ---------------------------------------------------------------------------

insert into smoke_results
select 'get_homepage_content function exists',
  to_regprocedure('public.get_homepage_content(integer,integer,integer,integer)') is not null,
  'consolidated homepage RPC is present';

insert into smoke_results
select 'complete_child_account_provisioning function exists',
  to_regprocedure('public.complete_child_account_provisioning(uuid,uuid,uuid,text,text,integer,text)') is not null,
  'atomic child provisioning RPC is present';

insert into smoke_results
select 'set_team_post_reaction function exists',
  to_regprocedure('public.set_team_post_reaction(uuid,boolean,text)') is not null,
  'atomic like/unlike toggle RPC is present';

insert into smoke_results
select 'create_team_post_with_poll function exists',
  to_regprocedure('public.create_team_post_with_poll(uuid,text,text,text,boolean,text[])') is not null,
  'atomic team post + poll option RPC is present';

insert into smoke_results
select 'consume_rate_limit function exists',
  to_regprocedure('public.consume_rate_limit(text,integer,integer)') is not null,
  'shared Postgres-backed rate limiter RPC is present';

insert into smoke_results
select 'diagnose_data_integrity function exists',
  to_regprocedure('public.diagnose_data_integrity()') is not null,
  'read-only integrity diagnostic RPC is present';

insert into smoke_results
select 'diagnose_wallet_reconciliation function exists',
  to_regprocedure('public.diagnose_wallet_reconciliation(integer)') is not null,
  'read-only wallet reconciliation diagnostic RPC is present';

-- ---------------------------------------------------------------------------
-- Evidence-based indexes must exist to keep hot list queries off full scans.
-- ---------------------------------------------------------------------------

insert into smoke_results
select 'team_posts_team_status_pinned_created_idx index exists',
  to_regclass('public.team_posts_team_status_pinned_created_idx') is not null,
  'team board listing index (team_id, status, is_pinned, created_at) is present';

insert into smoke_results
select 'wallet_ledger_wallet_created_idx index exists',
  to_regclass('public.wallet_ledger_wallet_created_idx') is not null,
  'wallet ledger listing index (wallet_account_id, created_at) is present';

-- ---------------------------------------------------------------------------
-- Diagnostics must stay strictly read-only: no mutating statements allowed.
-- ---------------------------------------------------------------------------

insert into smoke_results
select 'diagnose_data_integrity is read-only',
  not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'diagnose_data_integrity'
      and p.provolatile = 'v'
      and pg_get_functiondef(p.oid) ~* '\minsert into\M|\mupdate\M|\mdelete from\M'
  ),
  'diagnose_data_integrity body contains no insert/update/delete statements';

insert into smoke_results
select 'diagnose_wallet_reconciliation is read-only',
  not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'diagnose_wallet_reconciliation'
      and pg_get_functiondef(p.oid) ~* '\minsert into\M|\mupdate\M|\mdelete from\M'
  ),
  'diagnose_wallet_reconciliation body contains no insert/update/delete statements';

select check_name, passed, detail from smoke_results order by check_name;

do $$
declare
  failure_count integer;
begin
  select count(*) into failure_count from smoke_results where not passed;
  if failure_count > 0 then
    raise exception '% production hardening smoke check(s) failed', failure_count;
  end if;
end $$;

rollback;
