-- Targeted compatibility repair for admin create workflows.
-- Legacy venue columns/tables are retained because production migration history diverges.

alter table public.club_events add column if not exists venue text;
alter table public.fixtures add column if not exists venue text;
alter table public.training_sessions add column if not exists venue text;
alter table public.volunteer_shifts add column if not exists venue text;
alter table public.voucher_issuances add column if not exists canteen_venue text;

do $$
begin
  if to_regclass('public.venues') is not null then
    execute $sql$ update public.club_events e set venue=coalesce(e.venue,nullif(concat_ws(', ',nullif(v.name,''),nullif(v.suburb,'')),'')) from public.venues v where v.id=e.venue_id and e.venue is null $sql$;
    execute $sql$ update public.fixtures f set venue=coalesce(f.venue,nullif(concat_ws(', ',nullif(v.name,''),nullif(v.suburb,'')),'')) from public.venues v where v.id=f.venue_id and f.venue is null $sql$;
    execute $sql$ update public.training_sessions s set venue=coalesce(s.venue,nullif(concat_ws(', ',nullif(v.name,''),nullif(v.suburb,'')),'')) from public.venues v where v.id=s.venue_id and s.venue is null $sql$;
    execute $sql$ update public.volunteer_shifts s set venue=coalesce(s.venue,nullif(concat_ws(', ',nullif(v.name,''),nullif(v.suburb,'')),'')) from public.venues v where v.id=s.venue_id and s.venue is null $sql$;
  end if;
end
$$;

alter table public.club_events drop constraint if exists club_events_venue_length;
alter table public.club_events add constraint club_events_venue_length check(venue is null or char_length(venue)<=240);
alter table public.fixtures drop constraint if exists fixtures_venue_length;
alter table public.fixtures add constraint fixtures_venue_length check(venue is null or char_length(venue)<=240);
alter table public.training_sessions drop constraint if exists training_sessions_venue_length;
alter table public.training_sessions add constraint training_sessions_venue_length check(venue is null or char_length(venue)<=240);
alter table public.volunteer_shifts drop constraint if exists volunteer_shifts_venue_length;
alter table public.volunteer_shifts add constraint volunteer_shifts_venue_length check(venue is null or char_length(venue)<=240);
alter table public.voucher_issuances drop constraint if exists voucher_issuances_canteen_venue_length;
alter table public.voucher_issuances add constraint voucher_issuances_canteen_venue_length check(canteen_venue is null or char_length(canteen_venue)<=240);

-- Permit multiple official accounts on one platform while preventing duplicate URLs.
alter table public.social_profiles drop constraint if exists social_profiles_platform_key;
create unique index if not exists social_profiles_profile_url_key on public.social_profiles(profile_url);
grant select on public.social_profiles, public.social_posts to anon;
grant select,insert,update,delete on public.social_profiles,public.social_posts to authenticated;
grant all on public.social_profiles,public.social_posts to service_role;
drop policy if exists social_profiles_authorised_manage on public.social_profiles;
create policy social_profiles_authorised_manage on public.social_profiles for all to authenticated using(app_private.has_permission('social_profiles.manage')) with check(app_private.has_permission('social_profiles.manage'));
drop policy if exists social_posts_authorised_manage on public.social_posts;
create policy social_posts_authorised_manage on public.social_posts for all to authenticated using(app_private.has_permission('social_posts.manage')) with check(app_private.has_permission('social_posts.manage'));

grant select on public.sponsors to anon;
grant select,insert,update,delete on public.sponsors to authenticated;
grant all on public.sponsors to service_role;
drop policy if exists sponsors_public_active on public.sponsors;
create policy sponsors_public_active on public.sponsors for select to anon using(status='active');
drop policy if exists sponsors_manage_insert on public.sponsors;
create policy sponsors_manage_insert on public.sponsors for insert to authenticated with check(app_private.has_permission('sponsors.manage'));
drop policy if exists sponsors_manage_update on public.sponsors;
create policy sponsors_manage_update on public.sponsors for update to authenticated using(app_private.has_permission('sponsors.manage')) with check(app_private.has_permission('sponsors.manage'));
drop policy if exists sponsors_manage_delete on public.sponsors;
create policy sponsors_manage_delete on public.sponsors for delete to authenticated using(app_private.has_permission('sponsors.manage'));

-- Avoid family_members RLS selecting from itself and recursively breaking team-player joins.
create or replace function app_private.is_active_family_member(target_family_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.family_members fm where fm.family_id=target_family_id and fm.user_id=(select auth.uid()) and fm.status='active');
$$;
revoke all on function app_private.is_active_family_member(uuid) from public,anon;
grant execute on function app_private.is_active_family_member(uuid) to authenticated,service_role;
drop policy if exists family_members_read_related on public.family_members;
create policy family_members_read_related on public.family_members for select to authenticated using(user_id=(select auth.uid()) or app_private.has_permission('families.manage') or app_private.is_active_family_member(family_id));

alter table public.team_staff add column if not exists assigned_by uuid references public.profiles(id) on delete set null;
alter table public.team_players add column if not exists assigned_by uuid references public.profiles(id) on delete set null;

create or replace function public.save_team_assignment(target_user_id uuid,target_team_id uuid,target_position text,target_status text default 'active',target_starts_on date default null,target_ends_on date default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); team_season uuid; saved_id uuid; player_record_id uuid;
begin
  if actor is null or not(app_private.has_permission('team_memberships.manage') or app_private.has_permission('club_structure.manage') or app_private.has_permission('teams.manage',target_team_id)) then raise exception 'Not authorised'; end if;
  if target_position not in('player','coach','team_manager') then raise exception 'Unsupported team position'; end if;
  if target_status not in('active','inactive','left') then raise exception 'Invalid assignment status'; end if;
  if target_ends_on is not null and target_starts_on is not null and target_ends_on<target_starts_on then raise exception 'End date must follow start date'; end if;
  select season_id into team_season from public.teams where id=target_team_id;
  if team_season is null then raise exception 'Team not found'; end if;
  if not exists(select 1 from public.profiles where id=target_user_id) then raise exception 'User not found'; end if;
  if target_position='player' then
    insert into public.player_records(user_id,season_id,registration_status) values(target_user_id,team_season,'registered') on conflict(user_id,season_id) do update set updated_at=now() returning id into player_record_id;
    insert into public.team_players(team_id,player_id,starts_on,ends_on,status,assigned_by) values(target_team_id,player_record_id,target_starts_on,target_ends_on,target_status,actor) on conflict(team_id,player_id) do update set starts_on=excluded.starts_on,ends_on=excluded.ends_on,status=excluded.status,assigned_by=actor,updated_at=now() returning id into saved_id;
  else
    insert into public.team_staff(team_id,user_id,staff_role,starts_on,ends_on,status,assigned_by) values(target_team_id,target_user_id,target_position,target_starts_on,target_ends_on,target_status,actor) on conflict(team_id,user_id,staff_role) do update set starts_on=excluded.starts_on,ends_on=excluded.ends_on,status=excluded.status,assigned_by=actor,updated_at=now() returning id into saved_id;
  end if;
  perform app_private.write_audit_log('team_assignment.saved','team_assignment',saved_id,null,jsonb_build_object('user_id',target_user_id,'team_id',target_team_id,'position',target_position,'status',target_status),null);
  return saved_id;
end;
$$;
revoke all on function public.save_team_assignment(uuid,uuid,text,text,date,date) from public,anon;
grant execute on function public.save_team_assignment(uuid,uuid,text,text,date,date) to authenticated,service_role;