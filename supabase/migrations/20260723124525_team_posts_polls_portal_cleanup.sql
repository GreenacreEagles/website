-- Team boards, poll interactions and portal cleanup.
-- This migration keeps historical role request records but disables new member-driven requests.

insert into public.permissions (key, name, description)
values
  ('team_posts.create', 'Create team posts', 'Create announcements and polls for assigned teams.'),
  ('team_posts.moderate', 'Moderate team posts', 'Pin, close, archive or moderate team board content.')
on conflict (key) do update
set name = excluded.name,
    description = excluded.description;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.key in ('team_posts.create', 'team_posts.moderate')
where r.key in ('super_administrator', 'club_administrator')
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.key = 'team_posts.create'
where r.key in ('coach', 'assistant_coach', 'team_manager')
on conflict do nothing;

create table if not exists public.team_posts (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete restrict,
  title text not null check (char_length(trim(title)) between 3 and 140),
  body text,
  post_type text not null default 'announcement' check (post_type in ('announcement','poll','activity')),
  is_pinned boolean not null default false,
  allow_poll_results boolean not null default true,
  poll_closes_at timestamptz,
  status text not null default 'published' check (status in ('draft','published','archived')),
  published_at timestamptz not null default now(),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.team_post_reactions (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.team_posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  reaction text not null default 'acknowledged' check (reaction in ('acknowledged','thanks','attending','unavailable')),
  created_at timestamptz not null default now(),
  unique (post_id, user_id)
);

create table if not exists public.team_poll_options (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.team_posts(id) on delete cascade,
  label text not null check (char_length(trim(label)) between 1 and 80),
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  unique (post_id, label)
);

create table if not exists public.team_poll_responses (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.team_posts(id) on delete cascade,
  option_id uuid not null references public.team_poll_options(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  respondent_id uuid references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (post_id, user_id, respondent_id)
);

create table if not exists public.team_post_reads (
  post_id uuid not null references public.team_posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index if not exists team_posts_team_status_pinned_idx on public.team_posts (team_id, status, is_pinned desc, published_at desc);
create index if not exists team_reactions_post_idx on public.team_post_reactions (post_id);
create index if not exists team_poll_options_post_idx on public.team_poll_options (post_id, sort_order);
create index if not exists team_poll_responses_post_idx on public.team_poll_responses (post_id);

alter table public.team_posts enable row level security;
alter table public.team_post_reactions enable row level security;
alter table public.team_poll_options enable row level security;
alter table public.team_poll_responses enable row level security;
alter table public.team_post_reads enable row level security;

create or replace function app_private.can_access_team(target_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1
    from public.user_role_assignments ura
    join public.role_permissions rp on rp.role_id = ura.role_id
    join public.permissions p on p.id = rp.permission_id
    where ura.user_id = auth.uid()
      and ura.status = 'active'
      and ura.starts_at <= now()
      and (ura.ends_at is null or ura.ends_at > now())
      and (ura.team_id = target_team_id or ura.team_id is null)
      and p.key in ('teams.read', 'teams.manage', 'club_structure.manage', 'team_posts.create', 'team_posts.moderate', '*')
  )
  or exists (
    select 1
    from public.team_staff ts
    where ts.team_id = target_team_id
      and ts.user_id = auth.uid()
      and ts.status = 'active'
      and (ts.starts_on is null or ts.starts_on <= current_date)
      and (ts.ends_on is null or ts.ends_on >= current_date)
  )
  or exists (
    select 1
    from public.team_players tp
    join public.player_records pr on pr.id = tp.player_id
    where tp.team_id = target_team_id
      and tp.status = 'active'
      and pr.user_id = auth.uid()
  )
  or exists (
    select 1
    from public.team_players tp
    join public.player_records pr on pr.id = tp.player_id
    join public.family_members child_member on child_member.user_id = pr.user_id and child_member.status = 'active'
    join public.family_members guardian_member on guardian_member.family_id = child_member.family_id and guardian_member.status = 'active'
    where tp.team_id = target_team_id
      and tp.status = 'active'
      and guardian_member.user_id = auth.uid()
      and guardian_member.relationship in ('parent','guardian','carer')
  )
  or app_private.has_permission('teams.manage', target_team_id)
  or app_private.has_permission('club_structure.manage');
$$;

revoke all on function app_private.can_access_team(uuid) from public;
grant execute on function app_private.can_access_team(uuid) to authenticated;

create policy team_posts_accessible_read
on public.team_posts
for select
to authenticated
using (status <> 'draft' and app_private.can_access_team(team_id));

create policy team_posts_authorised_insert
on public.team_posts
for insert
to authenticated
with check (
  author_id = auth.uid()
  and (
    app_private.has_permission('team_posts.create', team_id)
    or app_private.has_permission('teams.manage', team_id)
  )
);

create policy team_posts_author_moderator_update
on public.team_posts
for update
to authenticated
using (
  author_id = auth.uid()
  or app_private.has_permission('team_posts.moderate', team_id)
  or app_private.has_permission('teams.manage', team_id)
)
with check (
  author_id = auth.uid()
  or app_private.has_permission('team_posts.moderate', team_id)
  or app_private.has_permission('teams.manage', team_id)
);

create policy team_post_reactions_accessible_read
on public.team_post_reactions
for select
to authenticated
using (exists (select 1 from public.team_posts tp where tp.id = post_id and app_private.can_access_team(tp.team_id)));

create policy team_post_reactions_own_upsert
on public.team_post_reactions
for insert
to authenticated
with check (user_id = auth.uid() and exists (select 1 from public.team_posts tp where tp.id = post_id and app_private.can_access_team(tp.team_id)));

create policy team_post_reactions_own_update
on public.team_post_reactions
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid() and exists (select 1 from public.team_posts tp where tp.id = post_id and app_private.can_access_team(tp.team_id)));

create policy team_poll_options_accessible_read
on public.team_poll_options
for select
to authenticated
using (exists (select 1 from public.team_posts tp where tp.id = post_id and app_private.can_access_team(tp.team_id)));

create policy team_poll_options_authorised_insert
on public.team_poll_options
for insert
to authenticated
with check (exists (select 1 from public.team_posts tp where tp.id = post_id and tp.author_id = auth.uid()));

create policy team_poll_responses_accessible_read
on public.team_poll_responses
for select
to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1
    from public.team_posts tp
    where tp.id = post_id
      and tp.allow_poll_results
      and app_private.can_access_team(tp.team_id)
  )
);

create policy team_poll_responses_own_insert
on public.team_poll_responses
for insert
to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.team_posts tp
    join public.team_poll_options tpo on tpo.post_id = tp.id
    where tp.id = post_id
      and tpo.id = option_id
      and tp.post_type = 'poll'
      and tp.status = 'published'
      and (tp.poll_closes_at is null or tp.poll_closes_at > now())
      and app_private.can_access_team(tp.team_id)
  )
);

create policy team_poll_responses_own_update
on public.team_poll_responses
for update
to authenticated
using (user_id = auth.uid())
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.team_posts tp
    join public.team_poll_options tpo on tpo.post_id = tp.id
    where tp.id = post_id
      and tpo.id = option_id
      and tp.post_type = 'poll'
      and tp.status = 'published'
      and (tp.poll_closes_at is null or tp.poll_closes_at > now())
      and app_private.can_access_team(tp.team_id)
  )
);

create policy team_post_reads_own_manage
on public.team_post_reads
for all
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid() and exists (select 1 from public.team_posts tp where tp.id = post_id and app_private.can_access_team(tp.team_id)));

grant select, insert, update on table public.team_posts to authenticated;
grant select, insert, update on table public.team_post_reactions to authenticated;
grant select, insert on table public.team_poll_options to authenticated;
grant select, insert, update on table public.team_poll_responses to authenticated;
grant select, insert, update on table public.team_post_reads to authenticated;

create or replace function public.member_team_ids()
returns table(team_id uuid, relationship text)
language sql
stable
security invoker
set search_path = public, extensions
as $$
  select distinct source.team_id, source.relationship
  from (
    select ura.team_id, 'role'::text as relationship
    from public.user_role_assignments ura
    join public.role_permissions rp on rp.role_id = ura.role_id
    join public.permissions p on p.id = rp.permission_id
    where ura.user_id = auth.uid()
      and ura.team_id is not null
      and ura.status = 'active'
      and ura.starts_at <= now()
      and (ura.ends_at is null or ura.ends_at > now())
      and p.key in ('teams.read', 'teams.manage', 'club_structure.manage', 'team_posts.create', 'team_posts.moderate', '*')
    union all
    select ts.team_id, ts.staff_role
    from public.team_staff ts
    where ts.user_id = auth.uid()
      and ts.status = 'active'
    union all
    select tp.team_id, 'player'
    from public.team_players tp
    join public.player_records pr on pr.id = tp.player_id
    where pr.user_id = auth.uid()
      and tp.status = 'active'
    union all
    select tp.team_id, 'guardian'
    from public.team_players tp
    join public.player_records pr on pr.id = tp.player_id
    join public.family_members child_member on child_member.user_id = pr.user_id and child_member.status = 'active'
    join public.family_members guardian_member on guardian_member.family_id = child_member.family_id and guardian_member.status = 'active'
    where guardian_member.user_id = auth.uid()
      and guardian_member.relationship in ('parent','guardian','carer')
      and tp.status = 'active'
  ) source
  where source.team_id is not null;
$$;

grant execute on function public.member_team_ids() to authenticated;

revoke execute on function public.request_role(uuid, uuid, uuid, text, text, text) from authenticated;
revoke execute on function public.withdraw_role_request(uuid, text) from authenticated;
revoke execute on function public.review_role_request(uuid, text, text, timestamptz, timestamptz) from authenticated;

drop policy if exists role_requests_create_own on public.role_requests;
drop policy if exists role_requests_review on public.role_requests;
drop policy if exists roles_requestable_read on public.roles;
drop policy if exists seasons_role_request_read on public.seasons;
drop policy if exists teams_role_request_read on public.teams;

comment on table public.role_requests is 'Deprecated historical access-request records. Member-driven role/team requests are disabled; administrators assign roles through Users.';
