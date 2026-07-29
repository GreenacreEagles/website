-- Final forward-only member portal structures. No venue or team-field cleanup.

create or replace function public.create_family_group(group_name text)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid=(select auth.uid()); family_id uuid;
begin
  if actor is null then raise exception 'You must be signed in'; end if;
  if exists(select 1 from public.managed_child_accounts where child_user_id=actor) then
    raise exception 'Child accounts cannot create family groups';
  end if;
  if char_length(trim(group_name)) not between 2 and 120 then raise exception 'Enter a valid group name'; end if;
  insert into public.families(name,created_by) values(trim(group_name),actor) returning id into family_id;
  insert into public.family_members(family_id,user_id,relationship,is_primary_guardian,can_manage,can_spend,status,accepted_at)
    values(family_id,actor,'guardian',true,true,true,'active',now());
  perform app_private.write_audit_log('family.created','family',family_id,null,
    jsonb_build_object('name',trim(group_name),'owner_id',actor),'Family group created');
  return family_id;
end $$;

revoke all on function public.create_family_group(text) from public,anon;

grant execute on function public.create_family_group(text) to authenticated,service_role;

alter table public.team_posts
  add column if not exists last_edited_at timestamptz,
  add column if not exists last_edited_by uuid references public.profiles(id) on delete set null,
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references public.profiles(id) on delete set null;

alter table public.match_reports
  add column if not exists match_description text,
  add column if not exists match_date date,
  add column if not exists venue text,
  add column if not exists report_body text,
  add column if not exists last_edited_at timestamptz,
  add column if not exists last_edited_by uuid references public.profiles(id) on delete set null,
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references public.profiles(id) on delete set null;

do $$ begin
 if exists(select 1 from public.team_post_reactions group by post_id,user_id having count(*)>1) then raise exception 'Duplicate team post reactions exist'; end if;
 if exists(select 1 from public.team_poll_responses group by post_id,user_id having count(*)>1) then raise exception 'Duplicate team poll responses exist'; end if;
end $$;

create unique index if not exists team_post_one_like_per_user
  on public.team_post_reactions(post_id,user_id);

create unique index if not exists team_poll_one_response_per_user
  on public.team_poll_responses(post_id,user_id);

create index if not exists team_posts_visible_feed_idx on public.team_posts(team_id,published_at desc)
  where status='active' and deleted_at is null;

create index if not exists match_reports_visible_idx on public.match_reports(team_id,created_at desc)
  where deleted_at is null;

alter table public.team_post_reactions drop constraint if exists team_post_reactions_reaction_check;

update public.team_post_reactions set reaction='like' where reaction<>'like';

alter table public.team_post_reactions add constraint team_post_reactions_reaction_check check (reaction='like');

alter table public.team_post_reactions alter column reaction set default 'like';

drop policy if exists team_post_reactions_own_delete on public.team_post_reactions;

create policy team_post_reactions_own_delete on public.team_post_reactions for delete to authenticated
  using (user_id=(select auth.uid()));

grant delete on public.team_post_reactions to authenticated;

drop policy if exists match_reports_team_read on public.match_reports;

create policy match_reports_team_read on public.match_reports for select to authenticated
  using (deleted_at is null and app_private.can_access_team(team_id));
