-- Member-requested volunteer access, family group creation, and simplified team publishing.

alter table if exists public.wwcc_submissions
  add column if not exists date_of_birth date,
  add column if not exists clearance_type text,
  add column if not exists verification_outcome text,
  add column if not exists verified_wwcc_number text,
  add column if not exists verified_expiry_date date,
  add column if not exists verified_clearance_type text,
  alter column document_file_id drop not null;

do $$ begin
  alter table public.wwcc_submissions add constraint wwcc_submissions_clearance_type_check
    check (clearance_type in ('volunteer','paid_worker'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.wwcc_submissions add constraint wwcc_submissions_verified_clearance_type_check
    check (verified_clearance_type is null or verified_clearance_type in ('volunteer','paid_worker'));
exception when duplicate_object then null; end $$;

update public.roles set may_request=true,
  description='Member-requested volunteer access that activates only after authorised external WWCC verification.'
where key='volunteer';

create or replace function public.request_volunteer_role()
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid=(select auth.uid()); volunteer_role_id uuid; assignment_id uuid; dob date;
begin
  if actor is null then raise exception 'You must be signed in'; end if;
  if exists(select 1 from public.managed_child_accounts where child_user_id=actor) then
    raise exception 'Child accounts cannot request volunteer access';
  end if;
  select date_of_birth into dob from public.profiles where id=actor;
  if dob is null or dob > current_date - interval '18 years' then
    raise exception 'Volunteer requests require an adult account with a date of birth';
  end if;
  select id into volunteer_role_id from public.roles where key='volunteer' and is_active;
  select id into assignment_id from public.user_role_assignments
   where user_id=actor and role_id=volunteer_role_id and revoked_at is null
   order by created_at desc limit 1;
  if assignment_id is null then
    insert into public.user_role_assignments(user_id,role_id,status,reason,starts_at)
    values(actor,volunteer_role_id,'pending','Member requested volunteer role; WWCC review required',now()) returning id into assignment_id;
  end if;
  insert into public.member_compliance(user_id,volunteer_status,wwcc_status)
    values(actor,'pending','not_supplied') on conflict(user_id) do nothing;
  perform app_private.write_audit_log('volunteer.requested','user_role_assignment',assignment_id,null,
    jsonb_build_object('user_id',actor,'status','pending'),'Member volunteer request');
  return assignment_id;
end $$;
revoke all on function public.request_volunteer_role() from public,anon;
grant execute on function public.request_volunteer_role() to authenticated,service_role;

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

create unique index if not exists team_post_one_like_per_user
  on public.team_post_reactions(post_id,user_id);
create unique index if not exists team_poll_one_response_per_user
  on public.team_poll_responses(post_id,user_id);
create index if not exists team_posts_visible_feed_idx on public.team_posts(team_id,published_at desc)
  where status='active' and deleted_at is null;
create index if not exists match_reports_visible_idx on public.match_reports(team_id,created_at desc)
  where deleted_at is null;


alter table public.team_post_reactions drop constraint if exists team_post_reactions_reaction_check;
alter table public.team_post_reactions add constraint team_post_reactions_reaction_check check (reaction='like');

drop policy if exists team_post_reactions_own_delete on public.team_post_reactions;
create policy team_post_reactions_own_delete on public.team_post_reactions for delete to authenticated
  using (user_id=(select auth.uid()));
grant delete on public.team_post_reactions to authenticated;

drop policy if exists wwcc_submissions_insert_own on public.wwcc_submissions;
create policy wwcc_submissions_insert_own on public.wwcc_submissions for insert to authenticated with check (
  user_id=(select auth.uid()) and status='pending' and reviewed_by is null and reviewed_at is null
  and clearance_type in ('volunteer','paid_worker')
  and exists(select 1 from public.user_role_assignments a join public.roles r on r.id=a.role_id
    where a.id=role_assignment_id and a.user_id=(select auth.uid()) and a.revoked_at is null and r.key='volunteer')
  and (document_file_id is null or exists(select 1 from public.file_records f where f.id=document_file_id
    and f.owner_id=(select auth.uid()) and f.visibility='private' and f.related_entity_type='wwcc_submission' and f.related_entity_id=id))
);

drop policy if exists match_reports_team_read on public.match_reports;
create policy match_reports_team_read on public.match_reports for select to authenticated
  using (deleted_at is null and app_private.can_access_team(team_id));
