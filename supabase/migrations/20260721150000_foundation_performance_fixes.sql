-- Follow-up fixes from Supabase performance advisors after the foundation apply.

create index if not exists event_registrations_attendee_id_fk_idx
  on public.event_registrations (attendee_id);

create index if not exists family_members_user_id_fk_idx
  on public.family_members (user_id);

create index if not exists player_records_season_id_fk_idx
  on public.player_records (season_id);

create index if not exists role_permissions_permission_id_fk_idx
  on public.role_permissions (permission_id);

create index if not exists team_players_player_id_fk_idx
  on public.team_players (player_id);

create index if not exists team_staff_user_id_fk_idx
  on public.team_staff (user_id);

create index if not exists user_role_assignments_season_id_fk_idx
  on public.user_role_assignments (season_id);

create index if not exists user_role_assignments_team_id_fk_idx
  on public.user_role_assignments (team_id);

create index if not exists volunteer_assignments_user_id_fk_idx
  on public.volunteer_assignments (user_id);

alter policy coaching_public_read
  on public.coaching_resources
  to anon
  using ((visibility = 'public'::text) and (status = 'published'::text));

alter policy coaching_staff_read
  on public.coaching_resources
  using (
    (status = 'published'::text)
    and (
      visibility = 'public'::text
      or app_private.has_permission('coaching_resources.read'::text)
    )
  );

alter policy files_public_read
  on public.file_records
  to anon
  using (visibility = 'public'::text);

alter policy files_owner_or_admin_read
  on public.file_records
  using (
    visibility = 'public'::text
    or owner_id = (select auth.uid())
    or app_private.has_permission('files.manage'::text)
  );

do $$
declare
  policy_record record;
  new_using text;
  new_check text;
  sql text;
begin
  for policy_record in
    select schemaname, tablename, policyname, qual, with_check
    from pg_policies
    where schemaname = 'public'
      and (
        coalesce(qual, '') like '%auth.uid()%'
        or coalesce(with_check, '') like '%auth.uid()%'
      )
  loop
    new_using := replace(policy_record.qual, 'auth.uid()', '(select auth.uid())');
    new_check := replace(policy_record.with_check, 'auth.uid()', '(select auth.uid())');
    sql := format('alter policy %I on %I.%I', policy_record.policyname, policy_record.schemaname, policy_record.tablename);

    if new_using is not null then
      sql := sql || format(' using (%s)', new_using);
    end if;

    if new_check is not null then
      sql := sql || format(' with check (%s)', new_check);
    end if;

    execute sql;
  end loop;
end;
$$;
