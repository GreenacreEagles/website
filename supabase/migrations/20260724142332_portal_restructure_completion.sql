-- Portal restructure completion.
-- Adds the missing access-request, child-account, voucher-template/campaign and
-- merchandise store-token primitives while normalising user-facing content status.

insert into public.permissions (key, name, description)
values
  ('team_access.review', 'Review team access requests', 'Approve or reject team access requests for assigned teams.'),
  ('team_members.manage', 'Manage team members', 'Directly add or remove users from teams.'),
  ('wallet.vouchers.manage', 'Manage wallet vouchers', 'Create voucher templates, campaigns and issue vouchers.'),
  ('merchandise.store_access', 'Access merchandise store', 'Generate secure short-lived merchandise store access tokens.'),
  ('children.manage', 'Manage child accounts', 'Create and administer managed child accounts.')
on conflict (key) do update
set name = excluded.name,
    description = excluded.description;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.key in ('team_access.review', 'team_members.manage', 'wallet.vouchers.manage', 'children.manage', 'merchandise.store_access')
where r.key in ('super_administrator', 'club_administrator')
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.key in ('team_access.review', 'team_members.manage', 'team_posts.create', 'merchandise.store_access')
where r.key in ('coach', 'team_manager')
on conflict do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.key in ('merchandise.store_access')
where r.key = 'general_user'
on conflict do nothing;

insert into public.roles (key, name, description, is_system, is_sensitive)
values
  ('canteen_staff', 'Canteen staff', 'Operational access for canteen orders, voucher scanning and wallet purchases.', true, true)
on conflict (key) do update
set name = excluded.name,
    description = excluded.description,
    is_sensitive = true;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.key in (
  'canteen.orders.manage',
  'canteen.vouchers.manage',
  'canteen.vouchers.redeem',
  'canteen.vouchers.reverse',
  'wallet.read'
)
where r.key = 'canteen_staff'
on conflict do nothing;

update public.profiles
set communication_sms = false
where communication_sms is distinct from false;

delete from public.notification_preferences
where channel = 'sms';

alter table public.notification_preferences
  drop constraint if exists notification_preferences_channel_check;

alter table public.notification_preferences
  add constraint notification_preferences_channel_check
  check (channel in ('in_app', 'email'));

create table if not exists public.team_access_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  requested_relationship text not null default 'parent' check (requested_relationship in ('player','parent','guardian','coach','manager','volunteer','other')),
  request_note text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  internal_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists team_access_requests_pending_unique
on public.team_access_requests (requester_id, team_id, requested_relationship)
where status = 'pending';

create index if not exists team_access_requests_team_status_idx
on public.team_access_requests (team_id, status, created_at desc);

drop trigger if exists team_access_requests_set_updated_at on public.team_access_requests;
create trigger team_access_requests_set_updated_at
before update on public.team_access_requests
for each row execute function app_private.set_updated_at();

alter table public.team_access_requests enable row level security;

create or replace function app_private.can_review_team_access(target_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select app_private.has_permission('club_structure.manage')
    or app_private.has_permission('teams.manage', target_team_id)
    or app_private.has_permission('team_access.review', target_team_id)
    or exists (
      select 1
      from public.team_staff ts
      where ts.team_id = target_team_id
        and ts.user_id = auth.uid()
        and ts.status = 'active'
        and ts.staff_role in ('coach', 'assistant_coach', 'team_manager')
        and (ts.starts_on is null or ts.starts_on <= current_date)
        and (ts.ends_on is null or ts.ends_on >= current_date)
    );
$$;

revoke all on function app_private.can_review_team_access(uuid) from public;

drop policy if exists team_access_requests_own_read on public.team_access_requests;
create policy team_access_requests_own_read
on public.team_access_requests
for select
to authenticated
using (requester_id = auth.uid() or app_private.can_review_team_access(team_id));

drop policy if exists team_access_requests_own_insert on public.team_access_requests;
create policy team_access_requests_own_insert
on public.team_access_requests
for insert
to authenticated
with check (
  requester_id = auth.uid()
  and status = 'pending'
  and not app_private.can_access_team(team_id)
);

drop policy if exists team_access_requests_reviewer_update on public.team_access_requests;
create policy team_access_requests_reviewer_update
on public.team_access_requests
for update
to authenticated
using (requester_id = auth.uid() or app_private.can_review_team_access(team_id))
with check (requester_id = auth.uid() or app_private.can_review_team_access(team_id));

grant select, insert, update on public.team_access_requests to authenticated;

create or replace function public.request_team_access(
  target_team_id uuid,
  requested_relationship text default 'parent',
  request_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  request_id uuid;
  safe_relationship text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if app_private.can_access_team(target_team_id) then
    raise exception 'You already have access to this team';
  end if;

  safe_relationship := coalesce(nullif(trim(requested_relationship), ''), 'parent');
  if safe_relationship not in ('player','parent','guardian','coach','manager','volunteer','other') then
    raise exception 'Invalid relationship';
  end if;

  insert into public.team_access_requests (requester_id, team_id, requested_relationship, request_note)
  values (auth.uid(), target_team_id, safe_relationship, nullif(trim(request_note), ''))
  on conflict (requester_id, team_id, requested_relationship)
  where status = 'pending'
  do update set request_note = excluded.request_note, updated_at = now()
  returning id into request_id;

  return request_id;
end;
$$;

create or replace function public.review_team_access_request(
  target_request_id uuid,
  review_status text,
  internal_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  request_row public.team_access_requests%rowtype;
  role_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if review_status not in ('approved','rejected') then
    raise exception 'Review status must be approved or rejected';
  end if;

  select *
  into request_row
  from public.team_access_requests
  where id = target_request_id
  for update;

  if not found then
    raise exception 'Request not found';
  end if;

  if request_row.status <> 'pending' then
    return request_row.id;
  end if;

  if not app_private.can_review_team_access(request_row.team_id) then
    raise exception 'Not authorised to review this request';
  end if;

  update public.team_access_requests
  set status = review_status,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      internal_note = nullif(trim(internal_note), '')
  where id = request_row.id;

  if review_status = 'approved' then
    select id into role_id
    from public.roles
    where key = case
      when request_row.requested_relationship in ('coach') then 'coach'
      when request_row.requested_relationship in ('manager') then 'team_manager'
      when request_row.requested_relationship in ('player') then 'player'
      else 'parent_guardian'
    end
    limit 1;

    if role_id is not null and not exists (
      select 1
      from public.user_role_assignments ura
      where ura.user_id = request_row.requester_id
        and ura.role_id = role_id
        and ura.team_id = request_row.team_id
        and ura.status = 'active'
    ) then
      insert into public.user_role_assignments (user_id, role_id, team_id, status, reason, assigned_by)
      values (
        request_row.requester_id,
        role_id,
        request_row.team_id,
        'active',
        'Approved team access request',
        auth.uid()
      );
    end if;
  end if;

  insert into public.notifications (recipient_id, title, body, category, related_entity_type, related_entity_id, action_url, dedupe_key)
  values (
    request_row.requester_id,
    case when review_status = 'approved' then 'Team access approved' else 'Team access rejected' end,
    case when review_status = 'approved' then 'Your team access request has been approved.' else 'Your team access request has been rejected.' end,
    'team',
    'team_access_request',
    request_row.id,
    '/portal/teams/',
    'team-access:' || request_row.id || ':' || review_status
  )
  on conflict (recipient_id, dedupe_key)
  where dedupe_key is not null
  do nothing;

  return request_row.id;
end;
$$;

revoke all on function public.request_team_access(uuid, text, text) from public;
revoke all on function public.review_team_access_request(uuid, text, text) from public;
grant execute on function public.request_team_access(uuid, text, text) to authenticated;
grant execute on function public.review_team_access_request(uuid, text, text) to authenticated;

create table if not exists public.managed_child_accounts (
  id uuid primary key default gen_random_uuid(),
  child_user_id uuid not null unique references public.profiles(id) on delete cascade,
  manager_user_id uuid not null references public.profiles(id) on delete cascade,
  family_id uuid references public.families(id) on delete set null,
  username text not null unique check (username ~ '^[a-z0-9][a-z0-9._-]{2,40}$'),
  login_disabled boolean not null default false,
  spending_limit_cents int check (spending_limit_cents is null or spending_limit_cents >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists managed_child_accounts_set_updated_at on public.managed_child_accounts;
create trigger managed_child_accounts_set_updated_at
before update on public.managed_child_accounts
for each row execute function app_private.set_updated_at();

alter table public.managed_child_accounts enable row level security;

drop policy if exists managed_child_accounts_family_read on public.managed_child_accounts;
create policy managed_child_accounts_family_read
on public.managed_child_accounts
for select
to authenticated
using (
  child_user_id = auth.uid()
  or manager_user_id = auth.uid()
  or app_private.has_permission('children.manage')
);

drop policy if exists managed_child_accounts_manager_update on public.managed_child_accounts;
create policy managed_child_accounts_manager_update
on public.managed_child_accounts
for update
to authenticated
using (manager_user_id = auth.uid() or app_private.has_permission('children.manage'))
with check (manager_user_id = auth.uid() or app_private.has_permission('children.manage'));

grant select, insert, update on public.managed_child_accounts to authenticated;
grant select, insert, update on public.managed_child_accounts to service_role;

create table if not exists public.store_access_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  token_hash text not null unique,
  purpose text not null default 'merchandise_store' check (purpose in ('merchandise_store')),
  redirect_path text not null default '/merchandise/',
  expires_at timestamptz not null,
  used_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  check (expires_at <= created_at + interval '24 hours')
);

create index if not exists store_access_tokens_user_idx
on public.store_access_tokens (user_id, created_at desc);

alter table public.store_access_tokens enable row level security;

drop policy if exists store_access_tokens_own_read on public.store_access_tokens;
create policy store_access_tokens_own_read
on public.store_access_tokens
for select
to authenticated
using (user_id = auth.uid() or app_private.has_permission('merchandise.manage'));

grant select on public.store_access_tokens to authenticated;
grant select, insert, update on public.store_access_tokens to service_role;

create table if not exists public.voucher_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  voucher_type text not null check (voucher_type in ('event_ticket','canteen_food','uniform','promotional','volunteer_reward','general_club','fixed_amount','specific_product','category','meal_deal','declining_balance')),
  value_cents int not null default 0 check (value_cents >= 0),
  usage_rules jsonb not null default '{}'::jsonb,
  status text not null default 'active' check (status in ('active','inactive')),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists voucher_templates_set_updated_at on public.voucher_templates;
create trigger voucher_templates_set_updated_at
before update on public.voucher_templates
for each row execute function app_private.set_updated_at();

create table if not exists public.voucher_campaigns (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.voucher_templates(id) on delete restrict,
  name text not null,
  target_type text not null check (target_type in ('role','team','family','volunteers','coaches','managers','players','parents','selected_users','all_eligible')),
  target_value text,
  recipient_count int not null default 0 check (recipient_count >= 0),
  expires_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (template_id, name)
);

alter table public.voucher_templates enable row level security;
alter table public.voucher_campaigns enable row level security;

drop policy if exists voucher_templates_read_authorised on public.voucher_templates;
create policy voucher_templates_read_authorised
on public.voucher_templates
for select
to authenticated
using (status = 'active' or app_private.has_permission('wallet.vouchers.manage') or app_private.has_permission('canteen.vouchers.manage'));

drop policy if exists voucher_templates_manage_authorised on public.voucher_templates;
create policy voucher_templates_manage_authorised
on public.voucher_templates
for all
to authenticated
using (app_private.has_permission('wallet.vouchers.manage') or app_private.has_permission('canteen.vouchers.manage'))
with check (app_private.has_permission('wallet.vouchers.manage') or app_private.has_permission('canteen.vouchers.manage'));

drop policy if exists voucher_campaigns_manage_authorised on public.voucher_campaigns;
create policy voucher_campaigns_manage_authorised
on public.voucher_campaigns
for all
to authenticated
using (app_private.has_permission('wallet.vouchers.manage') or app_private.has_permission('canteen.vouchers.manage'))
with check (app_private.has_permission('wallet.vouchers.manage') or app_private.has_permission('canteen.vouchers.manage'));

grant select, insert, update, delete on public.voucher_templates to authenticated;
grant select, insert, update, delete on public.voucher_campaigns to authenticated;

alter table public.voucher_issuances
  add column if not exists template_id uuid references public.voucher_templates(id) on delete set null,
  add column if not exists campaign_id uuid references public.voucher_campaigns(id) on delete set null,
  add column if not exists name text,
  add column if not exists description text;

alter table public.content_articles
  drop constraint if exists content_articles_workflow_status_check;

update public.content_articles
set workflow_status = case when workflow_status in ('published','scheduled') then 'active' else 'inactive' end
where workflow_status in ('draft','in_review','scheduled','published','archived');

alter table public.content_articles
  alter column workflow_status set default 'inactive';

alter table public.content_articles
  add constraint content_articles_workflow_status_check
  check (workflow_status in ('active','inactive'));

alter table public.club_announcements
  drop constraint if exists club_announcements_status_check;

update public.club_announcements
set status = case when status = 'published' then 'active' else 'inactive' end
where status in ('draft','published','archived');

alter table public.club_announcements
  alter column status set default 'inactive';

alter table public.club_announcements
  add constraint club_announcements_status_check
  check (status in ('active','inactive'));

alter table public.club_events
  drop constraint if exists club_events_status_check;

update public.club_events
set status = case when status = 'published' then 'active' else 'inactive' end
where status in ('draft','published','archived');

alter table public.club_events
  alter column status set default 'inactive';

alter table public.club_events
  add constraint club_events_status_check
  check (status in ('active','inactive','cancelled','completed'));

alter table public.coaching_resources
  drop constraint if exists coaching_resources_status_check;

update public.coaching_resources
set status = case when status = 'published' then 'active' else 'inactive' end
where status in ('draft','published','archived');

alter table public.coaching_resources
  alter column status set default 'inactive';

alter table public.coaching_resources
  add constraint coaching_resources_status_check
  check (status in ('active','inactive'));

alter table public.team_posts
  drop constraint if exists team_posts_status_check;

update public.team_posts
set status = case when status = 'published' then 'active' else 'inactive' end
where status in ('draft','published','archived');

alter table public.team_posts
  alter column status set default 'active';

alter table public.team_posts
  add constraint team_posts_status_check
  check (status in ('active','inactive'));

alter table public.merchandise_products
  drop constraint if exists merchandise_products_status_check;

update public.merchandise_products
set status = case when status = 'active' then 'active' else 'inactive' end
where status in ('draft','active','archived');

alter table public.merchandise_products
  alter column status set default 'active';

alter table public.merchandise_products
  add constraint merchandise_products_status_check
  check (status in ('active','inactive'));

drop policy if exists content_public_published on public.content_articles;
drop policy if exists content_public_active on public.content_articles;
create policy content_public_active
on public.content_articles
for select
to anon, authenticated
using (workflow_status = 'active' and (publish_at is null or publish_at <= now()));

drop policy if exists announcements_public_published on public.club_announcements;
drop policy if exists announcements_public_active on public.club_announcements;
create policy announcements_public_active
on public.club_announcements
for select
to anon, authenticated
using (status = 'active' and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now()));

drop policy if exists team_posts_accessible_read on public.team_posts;
create policy team_posts_accessible_read
on public.team_posts
for select
to authenticated
using (status = 'active' and app_private.can_access_team(team_id));

drop policy if exists coaching_resources_read on public.coaching_resources;
drop policy if exists coaching_resources_active_read on public.coaching_resources;
create policy coaching_resources_active_read
on public.coaching_resources
for select
to authenticated
using (
  status = 'active'
  and (
    visibility = 'public'
    or app_private.has_permission('coaching_resources.read')
    or app_private.has_permission('coaching_resources.manage')
  )
);

create or replace function app_private.notification_channel_enabled(
  p_user_id uuid,
  p_channel text,
  p_category text default 'general'
)
returns boolean
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  profile_allows boolean := true;
  preference_allows boolean;
begin
  if p_channel not in ('in_app','email') then
    return false;
  end if;

  if p_channel = 'email' then
    select coalesce(communication_email, true)
    into profile_allows
    from public.profiles
    where id = p_user_id;
  end if;

  select enabled
  into preference_allows
  from public.notification_preferences
  where user_id = p_user_id
    and channel = p_channel
    and category = p_category;

  if preference_allows is null then
    select enabled
    into preference_allows
    from public.notification_preferences
    where user_id = p_user_id
      and channel = p_channel
      and category = 'general';
  end if;

  return coalesce(profile_allows, false) and coalesce(preference_allows, true);
end;
$$;

create or replace function public.enqueue_admin_notification(
  p_recipient_id uuid,
  p_title text,
  p_body text,
  p_category text default 'general',
  p_channels text[] default array['in_app'],
  p_template_key text default null,
  p_payload jsonb default '{}'::jsonb,
  p_related_entity_type text default null,
  p_related_entity_id uuid default null,
  p_action_url text default null,
  p_dedupe_key text default null,
  p_scheduled_for timestamptz default now()
)
returns table (
  notification_id uuid,
  outbox_count int
)
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  created_notification_id uuid;
  queued_count int := 0;
  delivery_channel text;
begin
  if not app_private.has_permission('communications.manage') then
    raise exception 'You do not have permission to queue notifications';
  end if;

  if p_recipient_id is null then
    raise exception 'Recipient is required';
  end if;

  foreach delivery_channel in array p_channels loop
    if delivery_channel not in ('in_app', 'email') then
      raise exception 'Unsupported notification channel: %', delivery_channel;
    end if;
  end loop;

  if 'in_app' = any(p_channels) and app_private.notification_channel_enabled(p_recipient_id, 'in_app', p_category) then
    insert into public.notifications (
      recipient_id,
      title,
      body,
      category,
      related_entity_type,
      related_entity_id,
      action_url,
      dedupe_key,
      metadata
    )
    values (
      p_recipient_id,
      p_title,
      p_body,
      p_category,
      p_related_entity_type,
      p_related_entity_id,
      p_action_url,
      p_dedupe_key,
      p_payload
    )
    on conflict (recipient_id, dedupe_key)
    where dedupe_key is not null
    do update
      set title = excluded.title,
          body = excluded.body,
          category = excluded.category,
          related_entity_type = excluded.related_entity_type,
          related_entity_id = excluded.related_entity_id,
          action_url = excluded.action_url,
          metadata = excluded.metadata,
          created_at = now()
    returning id into created_notification_id;
  end if;

  foreach delivery_channel in array p_channels loop
    continue when delivery_channel = 'in_app';
    continue when not app_private.notification_channel_enabled(p_recipient_id, delivery_channel, p_category);

    insert into public.communication_outbox (
      recipient_id,
      channel,
      template_key,
      payload,
      category,
      related_entity_type,
      related_entity_id,
      dedupe_key,
      scheduled_for
    )
    values (
      p_recipient_id,
      delivery_channel,
      coalesce(p_template_key, 'admin_message'),
      p_payload || jsonb_build_object('title', p_title, 'body', p_body, 'action_url', p_action_url),
      p_category,
      p_related_entity_type,
      p_related_entity_id,
      case when p_dedupe_key is null then null else p_dedupe_key || ':' || delivery_channel end,
      p_scheduled_for
    )
    on conflict (dedupe_key)
    where dedupe_key is not null
    do update
      set payload = excluded.payload,
          scheduled_for = excluded.scheduled_for,
          status = 'pending',
          failure_reason = null,
          next_attempt_at = null;

    queued_count := queued_count + 1;
  end loop;

  notification_id := created_notification_id;
  outbox_count := queued_count;
  return next;
end;
$$;

revoke all on function public.enqueue_admin_notification(uuid, text, text, text, text[], text, jsonb, text, uuid, text, text, timestamptz) from public;
grant execute on function public.enqueue_admin_notification(uuid, text, text, text, text[], text, jsonb, text, uuid, text, text, timestamptz) to authenticated;

alter table public.teams
  drop constraint if exists teams_status_check;

update public.teams
set status = case when status = 'active' then 'active' else 'inactive' end
where status in ('draft','active','archived');

alter table public.teams
  alter column status set default 'active';

alter table public.teams
  add constraint teams_status_check
  check (status in ('active','inactive'));

alter table public.sponsors
  drop constraint if exists sponsors_status_check;

update public.sponsors
set status = case when status = 'active' then 'active' else 'inactive' end
where status in ('active','inactive','archived');

alter table public.sponsors
  alter column status set default 'active';

alter table public.sponsors
  add constraint sponsors_status_check
  check (status in ('active','inactive'));

create table if not exists public.wallet_qr_tokens (
  id uuid primary key default gen_random_uuid(),
  wallet_account_id uuid not null references public.wallet_accounts(id) on delete cascade,
  token_hash text not null unique,
  display_code text not null unique,
  status text not null default 'active' check (status in ('active','revoked')),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  unique (wallet_account_id, status)
);

alter table public.wallet_qr_tokens enable row level security;

drop policy if exists wallet_qr_tokens_owner_read on public.wallet_qr_tokens;
create policy wallet_qr_tokens_owner_read
on public.wallet_qr_tokens
for select
to authenticated
using (
  exists (
    select 1
    from public.wallet_accounts wa
    where wa.id = wallet_account_id
      and (wa.owner_id = auth.uid() or app_private.has_permission('canteen.orders.manage') or app_private.has_permission('wallet.read'))
  )
);

drop policy if exists wallet_qr_tokens_owner_insert on public.wallet_qr_tokens;
create policy wallet_qr_tokens_owner_insert
on public.wallet_qr_tokens
for insert
to authenticated
with check (
  exists (
    select 1
    from public.wallet_accounts wa
    where wa.id = wallet_account_id
      and wa.owner_id = auth.uid()
  )
);

grant select, insert, update on public.wallet_qr_tokens to authenticated;

create or replace function public.process_wallet_qr_purchase(
  wallet_display_code text,
  purchase_amount_cents int,
  purchase_description text default 'Canteen wallet purchase',
  idempotency_key text default null
)
returns table (
  wallet_id uuid,
  owner_id uuid,
  balance_after_cents int,
  ledger_entry_id uuid
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  token_row public.wallet_qr_tokens%rowtype;
  wallet_row public.wallet_accounts%rowtype;
  entry_id uuid;
  safe_key text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not (app_private.has_permission('canteen.orders.manage') or app_private.has_permission('wallet.adjust')) then
    raise exception 'Not authorised for wallet purchases';
  end if;

  if purchase_amount_cents <= 0 then
    raise exception 'Invalid purchase amount';
  end if;

  select *
  into token_row
  from public.wallet_qr_tokens
  where display_code = upper(trim(wallet_display_code))
    and status = 'active'
    and (expires_at is null or expires_at > now())
  for update;

  if not found then
    raise exception 'Wallet QR code is invalid or expired';
  end if;

  select *
  into wallet_row
  from public.wallet_accounts
  where id = token_row.wallet_account_id
  for update;

  if not found or wallet_row.status <> 'active' then
    raise exception 'Wallet is not available';
  end if;

  if app_private.wallet_balance_cents(wallet_row.id) < purchase_amount_cents then
    raise exception 'Insufficient wallet balance';
  end if;

  safe_key := coalesce(nullif(trim(idempotency_key), ''), 'canteen-wallet:' || token_row.id || ':' || auth.uid() || ':' || gen_random_uuid());

  entry_id := app_private.apply_wallet_entry(
    wallet_row.id,
    purchase_amount_cents,
    'debit',
    'canteen_purchase',
    safe_key,
    coalesce(nullif(trim(purchase_description), ''), 'Canteen wallet purchase'),
    wallet_row.owner_id
  );

  insert into public.notifications (recipient_id, title, body, category, related_entity_type, related_entity_id, action_url, dedupe_key)
  values (
    wallet_row.owner_id,
    'Wallet purchase completed',
    'A canteen wallet purchase has been processed.',
    'commerce',
    'wallet_ledger_entry',
    entry_id,
    '/portal/vouchers/',
    'wallet-purchase:' || entry_id
  )
  on conflict (recipient_id, dedupe_key)
  where dedupe_key is not null
  do nothing;

  return query
  select wallet_row.id, wallet_row.owner_id, app_private.wallet_balance_cents(wallet_row.id), entry_id;
end;
$$;

revoke all on function public.process_wallet_qr_purchase(text, int, text, text) from public;
grant execute on function public.process_wallet_qr_purchase(text, int, text, text) to authenticated;
