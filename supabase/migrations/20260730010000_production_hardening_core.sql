-- Production hardening: child provisioning, homepage RPC, atomic team board writes,
-- rate limiting, evidence-based indexes, and read-only integrity diagnostics.
-- Forward-only. Do not edit historical migrations.

-- ---------------------------------------------------------------------------
-- Rate limiting (shared across Workers isolates via Postgres)
-- ---------------------------------------------------------------------------
create table if not exists public.rate_limit_buckets (
  bucket_key text primary key,
  window_started_at timestamptz not null,
  request_count integer not null check (request_count >= 0),
  updated_at timestamptz not null default now()
);

alter table public.rate_limit_buckets enable row level security;
revoke all on table public.rate_limit_buckets from public, anon, authenticated;
grant select, insert, update, delete on table public.rate_limit_buckets to service_role;

create or replace function public.consume_rate_limit(
  bucket_key text,
  window_seconds integer,
  max_requests integer
)
returns table(allowed boolean, remaining integer, reset_at timestamptz, retry_after_seconds integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  now_ts timestamptz := now();
  window_start timestamptz;
  current_count integer;
  reset_ts timestamptz;
begin
  if bucket_key is null or char_length(bucket_key) < 3 or char_length(bucket_key) > 240 then
    raise exception 'Invalid rate limit key';
  end if;
  if window_seconds is null or window_seconds < 1 or window_seconds > 86400 then
    raise exception 'Invalid rate limit window';
  end if;
  if max_requests is null or max_requests < 1 or max_requests > 10000 then
    raise exception 'Invalid rate limit maximum';
  end if;

  insert into public.rate_limit_buckets as b(bucket_key, window_started_at, request_count, updated_at)
  values (bucket_key, now_ts, 1, now_ts)
  on conflict (bucket_key) do update
    set window_started_at = case
          when b.window_started_at + make_interval(secs => window_seconds) <= now_ts then now_ts
          else b.window_started_at
        end,
        request_count = case
          when b.window_started_at + make_interval(secs => window_seconds) <= now_ts then 1
          else b.request_count + 1
        end,
        updated_at = now_ts
  returning b.window_started_at, b.request_count
  into window_start, current_count;

  reset_ts := window_start + make_interval(secs => window_seconds);
  return query
  select
    current_count <= max_requests,
    greatest(max_requests - current_count, 0),
    reset_ts,
    greatest(ceil(extract(epoch from (reset_ts - now_ts)))::integer, 1);
end;
$$;

revoke all on function public.consume_rate_limit(text, integer, integer) from public, anon;
grant execute on function public.consume_rate_limit(text, integer, integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Child account provisioning state + transactional complete RPC
-- ---------------------------------------------------------------------------
create table if not exists public.child_account_provisioning (
  id uuid primary key default gen_random_uuid(),
  idempotency_key text not null unique,
  manager_user_id uuid not null references public.profiles(id) on delete cascade,
  family_id uuid not null references public.families(id) on delete cascade,
  username text not null,
  full_name text not null,
  spending_limit_cents integer check (spending_limit_cents is null or spending_limit_cents >= 0),
  auth_user_id uuid unique,
  status text not null default 'started'
    check (status in ('started','auth_created','completed','failed','compensated')),
  failure_code text,
  failure_detail text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create unique index if not exists child_account_provisioning_username_active_idx
  on public.child_account_provisioning (lower(username))
  where status in ('started','auth_created','completed');

alter table public.child_account_provisioning enable row level security;
revoke all on table public.child_account_provisioning from public, anon, authenticated;
grant select, insert, update on table public.child_account_provisioning to service_role;

create or replace function public.complete_child_account_provisioning(
  target_auth_user_id uuid,
  target_manager_user_id uuid,
  target_family_id uuid,
  target_username text,
  target_full_name text,
  target_spending_limit_cents integer default null,
  target_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  manager_ok boolean;
  wallet_id uuid;
  child_row public.managed_child_accounts%rowtype;
  member_id uuid;
  provisioning_id uuid;
  normalised_username text := lower(trim(target_username));
begin
  if target_auth_user_id is null or target_manager_user_id is null or target_family_id is null then
    raise exception 'Missing child provisioning identifiers';
  end if;
  if normalised_username is null or normalised_username !~ '^[a-z0-9][a-z0-9._-]{2,40}$' then
    raise exception 'Invalid child username';
  end if;
  if char_length(trim(target_full_name)) < 2 or char_length(trim(target_full_name)) > 120 then
    raise exception 'Invalid child name';
  end if;
  if target_spending_limit_cents is not null and target_spending_limit_cents < 0 then
    raise exception 'Invalid spending limit';
  end if;

  -- Service-role callers set request.jwt.claim.sub via PostgREST; fall back to manager id check.
  if actor is not null and actor <> target_manager_user_id and not app_private.has_permission('children.manage') then
    raise exception 'Not authorised';
  end if;

  select exists (
    select 1
    from public.family_members fm
    where fm.family_id = target_family_id
      and fm.user_id = target_manager_user_id
      and fm.status = 'active'
      and fm.can_manage = true
  ) into manager_ok;

  if not manager_ok and not coalesce(app_private.has_permission('children.manage'), false) then
    raise exception 'You cannot manage this family group';
  end if;

  if exists (
    select 1 from public.managed_child_accounts m
    where m.child_user_id = target_auth_user_id or lower(m.username) = normalised_username
  ) then
    select * into child_row from public.managed_child_accounts
    where child_user_id = target_auth_user_id or lower(username) = normalised_username
    limit 1;
    select wa.id into wallet_id from public.wallet_accounts wa where wa.owner_id = child_row.child_user_id limit 1;
    return jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'child_user_id', child_row.child_user_id,
      'wallet_account_id', wallet_id,
      'managed_child_id', child_row.id
    );
  end if;

  insert into public.profiles as p (
    id, full_name, relationship_to_club, communication_email, communication_sms,
    onboarding_completed_at, account_status
  ) values (
    target_auth_user_id, trim(target_full_name), 'GEFC User', false, false, now(), 'active'
  )
  on conflict (id) do update
    set full_name = excluded.full_name,
        relationship_to_club = excluded.relationship_to_club,
        communication_email = false,
        communication_sms = false,
        onboarding_completed_at = coalesce(p.onboarding_completed_at, excluded.onboarding_completed_at),
        account_status = 'active',
        updated_at = now();

  insert into public.managed_child_accounts (
    child_user_id, manager_user_id, family_id, username, spending_limit_cents
  ) values (
    target_auth_user_id, target_manager_user_id, target_family_id, normalised_username, target_spending_limit_cents
  )
  on conflict (child_user_id) do update
    set manager_user_id = excluded.manager_user_id,
        family_id = excluded.family_id,
        username = excluded.username,
        spending_limit_cents = excluded.spending_limit_cents,
        updated_at = now()
  returning * into child_row;

  insert into public.family_members (
    family_id, user_id, relationship, status, can_manage, can_spend, spending_limit_cents
  ) values (
    target_family_id, target_auth_user_id, 'child', 'active', false, false, target_spending_limit_cents
  )
  on conflict do nothing;

  select fm.id into member_id
  from public.family_members fm
  where fm.family_id = target_family_id and fm.user_id = target_auth_user_id
  limit 1;

  if member_id is null then
    -- Some schemas use a unique (family_id, user_id); retry update path.
    update public.family_members
      set relationship = 'child',
          status = 'active',
          can_manage = false,
          can_spend = false,
          spending_limit_cents = target_spending_limit_cents,
          updated_at = now()
    where family_id = target_family_id and user_id = target_auth_user_id
    returning id into member_id;
  end if;

  if member_id is null then
    raise exception 'Family membership could not be created';
  end if;

  insert into public.wallet_accounts (owner_id, account_type, status)
  values (target_auth_user_id, 'user', 'active')
  on conflict do nothing;

  select wa.id into wallet_id
  from public.wallet_accounts wa
  where wa.owner_id = target_auth_user_id
  limit 1;

  if wallet_id is null then
    raise exception 'Child wallet could not be provisioned';
  end if;

  if target_idempotency_key is not null then
    insert into public.child_account_provisioning (
      idempotency_key, manager_user_id, family_id, username, full_name,
      spending_limit_cents, auth_user_id, status, completed_at
    ) values (
      target_idempotency_key, target_manager_user_id, target_family_id, normalised_username,
      trim(target_full_name), target_spending_limit_cents, target_auth_user_id, 'completed', now()
    )
    on conflict (idempotency_key) do update
      set auth_user_id = excluded.auth_user_id,
          status = 'completed',
          completed_at = now(),
          updated_at = now(),
          failure_code = null,
          failure_detail = null
    returning id into provisioning_id;
  end if;

  perform app_private.write_audit_log(
    'child.provisioned',
    'managed_child_account',
    child_row.id,
    null,
    jsonb_build_object(
      'child_user_id', target_auth_user_id,
      'family_id', target_family_id,
      'username', normalised_username,
      'wallet_account_id', wallet_id,
      'idempotency_key', target_idempotency_key
    ),
    'Managed child account provisioned'
  );

  return jsonb_build_object(
    'ok', true,
    'idempotent', false,
    'child_user_id', target_auth_user_id,
    'wallet_account_id', wallet_id,
    'managed_child_id', child_row.id,
    'family_member_id', member_id,
    'provisioning_id', provisioning_id
  );
end;
$$;

revoke all on function public.complete_child_account_provisioning(uuid,uuid,uuid,text,text,integer,text) from public, anon;
grant execute on function public.complete_child_account_provisioning(uuid,uuid,uuid,text,text,integer,text) to service_role;

-- ---------------------------------------------------------------------------
-- Homepage consolidated content (one round-trip for public home)
-- ---------------------------------------------------------------------------
create or replace function public.get_homepage_content(
  article_limit integer default 3,
  social_limit integer default 3,
  sponsor_limit integer default 3,
  event_limit integer default 3
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  a_limit integer := least(greatest(coalesce(article_limit, 3), 1), 6);
  s_limit integer := least(greatest(coalesce(social_limit, 3), 1), 6);
  sp_limit integer := least(greatest(coalesce(sponsor_limit, 3), 1), 6);
  e_limit integer := least(greatest(coalesce(event_limit, 3), 1), 6);
  today date := current_date;
  now_ts timestamptz := now();
begin
  return jsonb_build_object(
    'articles', coalesce((
      select jsonb_agg(row_to_json(x))
      from (
        select id, title, slug, summary, category, featured_image_url, publish_at, updated_at, tags
        from public.content_articles
        where workflow_status = 'active'
          and (publish_at is null or publish_at <= now_ts)
        order by publish_at desc nulls last, updated_at desc
        limit a_limit
      ) x
    ), '[]'::jsonb),
    'social_posts', coalesce((
      select jsonb_agg(row_to_json(x))
      from (
        select id, platform, title, caption, post_url, image_object_key, image_alt_text, published_at, featured
        from public.social_posts
        where active = true
        order by featured desc, sort_order, published_at desc nulls last, created_at desc
        limit s_limit
      ) x
    ), '[]'::jsonb),
    'sponsors', coalesce((
      select jsonb_agg(row_to_json(x))
      from (
        select id, name, tier, description, website_url, logo_object_key, logo_url, display_priority
        from public.sponsors
        where status = 'active'
          and (starts_on is null or starts_on <= today)
          and (ends_on is null or ends_on >= today)
        order by display_priority, name
        limit sp_limit
      ) x
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(row_to_json(x))
      from (
        select e.id, e.slug, e.title, e.description, e.image_object_key, e.image_url, e.starts_at, e.ends_at, e.venue,
               (
                 select coalesce(jsonb_agg(jsonb_build_object(
                   'price_cents', t.price_cents, 'currency', t.currency, 'capacity', t.capacity, 'active', t.active
                 )), '[]'::jsonb)
                 from public.club_event_ticket_types t
                 where t.event_id = e.id and t.active = true
               ) as ticket_types
        from public.club_events e
        where e.status = 'active' and e.visibility = 'public' and e.starts_at > now_ts
        order by e.starts_at
        limit e_limit
      ) x
    ), '[]'::jsonb),
    'spotlight_team', (
      select row_to_json(x)
      from (
        select t.id, t.slug, t.name, t.division, t.summary, t.image_object_key, t.sort_order,
               s.name as season_name, c.name as competition_name
        from public.teams t
        left join public.seasons s on s.id = t.season_id
        left join public.competitions c on c.id = t.competition_id
        where t.status = 'active' and t.public = true
        order by s.year desc nulls last, t.sort_order, t.name
        limit 1
      ) x
    ),
    'active_team_count', (
      select count(*)::integer from public.teams where status = 'active'
    ),
    'announcement', (
      select row_to_json(x)
      from (
        select id, title, message, priority
        from public.club_announcements
        where status = 'active'
          and audience in ('public', 'members')
          and (starts_at is null or starts_at <= now_ts)
          and (ends_at is null or ends_at > now_ts)
        order by priority
        limit 1
      ) x
    )
  );
end;
$$;

revoke all on function public.get_homepage_content(integer,integer,integer,integer) from public;
grant execute on function public.get_homepage_content(integer,integer,integer,integer) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Atomic team post reaction + poll creation
-- ---------------------------------------------------------------------------
create or replace function public.set_team_post_reaction(
  target_post_id uuid,
  desired_liked boolean,
  request_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  existing_id uuid;
  post_team uuid;
  liked boolean;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  if target_post_id is null then raise exception 'Post is required'; end if;

  select team_id into post_team
  from public.team_posts
  where id = target_post_id and status = 'active' and deleted_at is null;

  if post_team is null then raise exception 'Post not found'; end if;
  if not app_private.can_access_team(post_team) then raise exception 'Not authorised'; end if;

  select id into existing_id
  from public.team_post_reactions
  where post_id = target_post_id and user_id = actor
  for update;

  if desired_liked then
    if existing_id is null then
      insert into public.team_post_reactions (post_id, user_id, reaction)
      values (target_post_id, actor, 'like')
      on conflict (post_id, user_id) do nothing;
    end if;
    liked := true;
  else
    if existing_id is not null then
      delete from public.team_post_reactions where id = existing_id and user_id = actor;
    end if;
    liked := false;
  end if;

  return jsonb_build_object('ok', true, 'liked', liked, 'post_id', target_post_id, 'request_key', request_key);
end;
$$;

revoke all on function public.set_team_post_reaction(uuid, boolean, text) from public, anon;
grant execute on function public.set_team_post_reaction(uuid, boolean, text) to authenticated, service_role;

create or replace function public.create_team_post_with_poll(
  target_team_id uuid,
  target_title text,
  target_body text default null,
  target_post_type text default 'announcement',
  target_is_pinned boolean default false,
  target_poll_options text[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  post_id uuid;
  options text[];
  option_label text;
  idx integer := 0;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  if target_team_id is null then raise exception 'Team is required'; end if;
  if char_length(trim(target_title)) < 3 or char_length(trim(target_title)) > 140 then
    raise exception 'Invalid title';
  end if;
  if target_body is not null and char_length(target_body) > 4000 then
    raise exception 'Post body is too long';
  end if;
  if target_post_type not in ('announcement', 'poll') then
    raise exception 'Invalid post type';
  end if;

  if not app_private.can_manage_team_operations(target_team_id) then
    raise exception 'Not authorised to post to this team';
  end if;

  if target_post_type = 'poll' then
    options := coalesce(nullif(target_poll_options, '{}'::text[]), array['Yes','No']::text[]);
    if coalesce(array_length(options, 1), 0) < 2 or coalesce(array_length(options, 1), 0) > 20 then
      raise exception 'Polls require between 2 and 20 options';
    end if;
  else
    options := array[]::text[];
  end if;

  insert into public.team_posts (
    team_id, author_id, title, body, post_type, is_pinned, status
  ) values (
    target_team_id, actor, trim(target_title), nullif(trim(coalesce(target_body, '')), ''),
    target_post_type, coalesce(target_is_pinned, false), 'active'
  ) returning id into post_id;

  if target_post_type = 'poll' then
    foreach option_label in array options loop
      if char_length(trim(option_label)) < 1 or char_length(trim(option_label)) > 80 then
        raise exception 'Invalid poll option';
      end if;
      insert into public.team_poll_options (post_id, label, sort_order)
      values (post_id, trim(option_label), idx);
      idx := idx + 1;
    end loop;
  end if;

  perform app_private.write_audit_log(
    'team_post.created',
    'team_post',
    post_id,
    null,
    jsonb_build_object('team_id', target_team_id, 'post_type', target_post_type, 'options', options),
    null
  );

  return jsonb_build_object('ok', true, 'post_id', post_id, 'option_count', coalesce(array_length(options, 1), 0));
end;
$$;

revoke all on function public.create_team_post_with_poll(uuid,text,text,text,boolean,text[]) from public, anon;
grant execute on function public.create_team_post_with_poll(uuid,text,text,text,boolean,text[]) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Evidence-based indexes (audit M1)
-- ---------------------------------------------------------------------------
create index if not exists team_posts_team_status_pinned_created_idx
  on public.team_posts (team_id, status, is_pinned desc, created_at desc)
  where deleted_at is null;

create index if not exists wallet_ledger_wallet_created_idx
  on public.wallet_ledger_entries (wallet_account_id, created_at desc);

create index if not exists content_articles_active_publish_idx
  on public.content_articles (publish_at desc nulls last, updated_at desc)
  where workflow_status = 'active';

create index if not exists notifications_recipient_unread_created_idx
  on public.notifications (recipient_id, created_at desc)
  where read_at is null;

create index if not exists family_members_family_user_idx
  on public.family_members (family_id, user_id);

create index if not exists rate_limit_buckets_updated_idx
  on public.rate_limit_buckets (updated_at);
