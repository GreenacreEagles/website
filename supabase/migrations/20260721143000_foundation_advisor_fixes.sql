-- Advisor fixes after applying the foundation migration.

create or replace function app_private.set_updated_at()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function app_private.current_user_id()
returns uuid
language sql
stable
set search_path = public, extensions
as $$
  select auth.uid();
$$;

create policy role_assignment_history_admin_read on public.role_assignment_history
for select to authenticated
using (app_private.has_permission('roles.assign') or app_private.has_permission('audit.read'));

do $$
declare
  fk record;
  index_name text;
begin
  for fk in
    select
      n.nspname as schema_name,
      t.relname as table_name,
      c.conname as constraint_name,
      array_agg(a.attname order by u.ord) as column_names
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    join unnest(c.conkey) with ordinality as u(attnum, ord) on true
    join pg_attribute a on a.attrelid = t.oid and a.attnum = u.attnum
    where c.contype = 'f'
      and n.nspname = 'public'
      and not exists (
        select 1
        from pg_index i
        where i.indrelid = c.conrelid
          and i.indkey::smallint[] @> c.conkey
      )
    group by n.nspname, t.relname, c.conname
  loop
    index_name := left(fk.table_name || '_' || array_to_string(fk.column_names, '_') || '_fk_idx', 63);
    execute format(
      'create index if not exists %I on %I.%I (%s)',
      index_name,
      fk.schema_name,
      fk.table_name,
      (
        select string_agg(format('%I', column_name), ', ')
        from unnest(fk.column_names) as column_name
      )
    );
  end loop;
end;
$$;

do $$
declare
  pol record;
  has_other_select boolean;
begin
  for pol in
    select
      schemaname,
      tablename,
      policyname,
      roles,
      qual,
      with_check
    from pg_policies
    where schemaname = 'public'
      and cmd = 'ALL'
  loop
    select exists (
      select 1
      from pg_policies existing
      where existing.schemaname = pol.schemaname
        and existing.tablename = pol.tablename
        and existing.cmd = 'SELECT'
        and existing.roles && pol.roles
    )
    into has_other_select;

    execute format('drop policy %I on %I.%I', pol.policyname, pol.schemaname, pol.tablename);

    if not has_other_select then
      execute format(
        'create policy %I on %I.%I for select to authenticated using (%s)',
        left(pol.policyname || '_select', 63),
        pol.schemaname,
        pol.tablename,
        pol.qual
      );
    end if;

    execute format(
      'create policy %I on %I.%I for insert to authenticated with check (%s)',
      left(pol.policyname || '_insert', 63),
      pol.schemaname,
      pol.tablename,
      coalesce(pol.with_check, pol.qual)
    );

    execute format(
      'create policy %I on %I.%I for update to authenticated using (%s) with check (%s)',
      left(pol.policyname || '_update', 63),
      pol.schemaname,
      pol.tablename,
      pol.qual,
      coalesce(pol.with_check, pol.qual)
    );

    execute format(
      'create policy %I on %I.%I for delete to authenticated using (%s)',
      left(pol.policyname || '_delete', 63),
      pol.schemaname,
      pol.tablename,
      pol.qual
    );
  end loop;
end;
$$;
