-- Squad, staff and match-report operations for assigned team staff.

create or replace function app_private.can_manage_team_operations(target_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1
    from public.team_staff ts
    where ts.team_id = target_team_id
      and ts.user_id = auth.uid()
      and ts.status = 'active'
      and ts.staff_role in ('coach', 'assistant_coach', 'team_manager')
      and (ts.starts_on is null or ts.starts_on <= current_date)
      and (ts.ends_on is null or ts.ends_on >= current_date)
  )
  or app_private.has_permission('teams.manage', target_team_id)
  or app_private.has_permission('team_posts.create', target_team_id)
  or app_private.has_permission('match_reports.submit', target_team_id)
  or app_private.has_permission('club_structure.manage');
$$;

revoke all on function app_private.can_manage_team_operations(uuid) from public;
grant execute on function app_private.can_manage_team_operations(uuid) to authenticated;

drop policy if exists team_posts_authorised_insert on public.team_posts;
create policy team_posts_authorised_insert
on public.team_posts
for insert
to authenticated
with check (
  author_id = auth.uid()
  and app_private.can_manage_team_operations(team_id)
);

drop policy if exists team_posts_author_moderator_update on public.team_posts;
create policy team_posts_author_moderator_update
on public.team_posts
for update
to authenticated
using (
  (author_id = auth.uid() and app_private.can_manage_team_operations(team_id))
  or app_private.has_permission('team_posts.moderate', team_id)
  or app_private.has_permission('teams.manage', team_id)
)
with check (
  (author_id = auth.uid() and app_private.can_manage_team_operations(team_id))
  or app_private.has_permission('team_posts.moderate', team_id)
  or app_private.has_permission('teams.manage', team_id)
);

drop policy if exists match_reports_author_team_admin on public.match_reports;
create policy match_reports_author_team_admin
on public.match_reports
for select
to authenticated
using (
  author_id = auth.uid()
  or app_private.can_manage_team_operations(team_id)
  or app_private.has_permission('match_reports.read', team_id)
  or app_private.has_permission('match_reports.review')
);

drop policy if exists match_reports_submit on public.match_reports;
create policy match_reports_submit
on public.match_reports
for insert
to authenticated
with check (
  author_id = auth.uid()
  and app_private.can_manage_team_operations(team_id)
);

drop policy if exists match_reports_update_author_or_reviewer on public.match_reports;
create policy match_reports_update_author_or_reviewer
on public.match_reports
for update
to authenticated
using (
  (author_id = auth.uid() and status in ('draft', 'changes_requested'))
  or app_private.has_permission('match_reports.review')
)
with check (
  (author_id = auth.uid() and status in ('draft', 'submitted'))
  or app_private.has_permission('match_reports.review')
);

create index if not exists match_reports_team_status_created_idx on public.match_reports (team_id, status, created_at desc);

drop policy if exists team_staff_read_team on public.team_staff;
create policy team_staff_read_team
on public.team_staff
for select
to authenticated
using (
  user_id = auth.uid()
  or app_private.can_access_team(team_id)
  or app_private.has_permission('teams.manage', team_id)
);

drop policy if exists team_players_read_team_staff on public.team_players;
create policy team_players_read_team_staff
on public.team_players
for select
to authenticated
using (
  app_private.can_access_team(team_id)
  or app_private.has_permission('teams.manage', team_id)
);
