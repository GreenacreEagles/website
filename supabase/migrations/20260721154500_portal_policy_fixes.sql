do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'roles' and policyname = 'roles_requestable_read') then
    create policy roles_requestable_read
      on public.roles
      for select
      to authenticated
      using (may_request and key <> 'super_administrator');
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'seasons' and policyname = 'seasons_role_request_read') then
    create policy seasons_role_request_read
      on public.seasons
      for select
      to authenticated
      using (status in ('draft', 'active'));
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'teams' and policyname = 'teams_role_request_read') then
    create policy teams_role_request_read
      on public.teams
      for select
      to authenticated
      using (status in ('draft', 'active'));
  end if;
end;
$$;
