-- Notification preferences and a reliable communication outbox worker contract.

create table if not exists public.notification_preferences (
  user_id uuid not null references public.profiles(id) on delete cascade,
  channel text not null check (channel in ('in_app', 'email', 'sms')),
  category text not null default 'general' check (category ~ '^[a-z0-9_:-]+$'),
  enabled boolean not null default true,
  quiet_hours_start time,
  quiet_hours_end time,
  updated_at timestamptz not null default now(),
  primary key (user_id, channel, category)
);

create index if not exists notification_preferences_user_idx
on public.notification_preferences (user_id, channel, enabled);

alter table public.notification_preferences enable row level security;

drop policy if exists notification_preferences_own_read on public.notification_preferences;
create policy notification_preferences_own_read
on public.notification_preferences
for select
to authenticated
using (user_id = auth.uid() or app_private.has_permission('communications.manage'));

drop policy if exists notification_preferences_own_insert on public.notification_preferences;
create policy notification_preferences_own_insert
on public.notification_preferences
for insert
to authenticated
with check (user_id = auth.uid() or app_private.has_permission('communications.manage'));

drop policy if exists notification_preferences_own_update on public.notification_preferences;
create policy notification_preferences_own_update
on public.notification_preferences
for update
to authenticated
using (user_id = auth.uid() or app_private.has_permission('communications.manage'))
with check (user_id = auth.uid() or app_private.has_permission('communications.manage'));

grant select, insert, update on public.notification_preferences to authenticated;

alter table public.notifications
  add column if not exists category text not null default 'general',
  add column if not exists action_url text,
  add column if not exists expires_at timestamptz,
  add column if not exists dedupe_key text,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

create index if not exists notifications_recipient_unread_idx
on public.notifications (recipient_id, created_at desc)
where read_at is null;

create index if not exists notifications_related_idx
on public.notifications (related_entity_type, related_entity_id)
where related_entity_type is not null and related_entity_id is not null;

create unique index if not exists notifications_recipient_dedupe_idx
on public.notifications (recipient_id, dedupe_key)
where dedupe_key is not null;

grant select, insert, update on public.notifications to authenticated;

alter table public.communication_outbox
  add column if not exists category text not null default 'general',
  add column if not exists dedupe_key text,
  add column if not exists priority int not null default 0,
  add column if not exists attempts int not null default 0 check (attempts >= 0),
  add column if not exists max_attempts int not null default 5 check (max_attempts > 0),
  add column if not exists locked_at timestamptz,
  add column if not exists locked_by text,
  add column if not exists last_attempt_at timestamptz,
  add column if not exists next_attempt_at timestamptz,
  add column if not exists processed_at timestamptz,
  add column if not exists external_message_id text;

alter table public.communication_outbox
  drop constraint if exists communication_outbox_status_check;

alter table public.communication_outbox
  add constraint communication_outbox_status_check
  check (status in ('pending', 'processing', 'sent', 'failed', 'cancelled'));

create index if not exists communication_outbox_pending_idx
on public.communication_outbox (status, scheduled_for, priority desc, created_at)
where status in ('pending', 'failed');

create index if not exists communication_outbox_recipient_idx
on public.communication_outbox (recipient_id, created_at desc);

create unique index if not exists communication_outbox_dedupe_idx
on public.communication_outbox (dedupe_key)
where dedupe_key is not null;

grant select, insert, update on public.communication_outbox to authenticated;
grant select, insert, update on public.communication_outbox to service_role;

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
  if p_channel = 'email' then
    select coalesce(communication_email, true)
    into profile_allows
    from public.profiles
    where id = p_user_id;
  elsif p_channel = 'sms' then
    select coalesce(communication_sms, false)
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

revoke all on function app_private.notification_channel_enabled(uuid, text, text) from public;

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
    if delivery_channel not in ('in_app', 'email', 'sms') then
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
      case
        when p_dedupe_key is null then null
        else p_dedupe_key || ':' || delivery_channel
      end,
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

create or replace function public.claim_communication_outbox(
  p_worker_id text,
  p_limit int default 25
)
returns setof public.communication_outbox
language plpgsql
security invoker
set search_path = public, app_private
as $$
begin
  if current_user <> 'service_role' then
    raise exception 'Only the service role can claim communication jobs';
  end if;

  return query
  with claimable as (
    select id
    from public.communication_outbox
    where status in ('pending', 'failed')
      and scheduled_for <= now()
      and coalesce(next_attempt_at, scheduled_for) <= now()
      and attempts < max_attempts
      and (locked_at is null or locked_at < now() - interval '15 minutes')
    order by priority desc, scheduled_for asc, created_at asc
    limit greatest(1, least(coalesce(p_limit, 25), 100))
    for update skip locked
  )
  update public.communication_outbox outbox
  set status = 'processing',
      locked_at = now(),
      locked_by = nullif(trim(p_worker_id), ''),
      attempts = attempts + 1,
      last_attempt_at = now(),
      failure_reason = null
  from claimable
  where outbox.id = claimable.id
  returning outbox.*;
end;
$$;

revoke all on function public.claim_communication_outbox(text, int) from public;
grant execute on function public.claim_communication_outbox(text, int) to service_role;

create or replace function public.complete_communication_outbox(
  p_outbox_id uuid,
  p_worker_id text,
  p_external_message_id text default null
)
returns boolean
language plpgsql
security invoker
set search_path = public, app_private
as $$
begin
  if current_user <> 'service_role' then
    raise exception 'Only the service role can complete communication jobs';
  end if;

  update public.communication_outbox
  set status = 'sent',
      sent_at = now(),
      processed_at = now(),
      locked_at = null,
      locked_by = null,
      external_message_id = nullif(trim(p_external_message_id), ''),
      failure_reason = null
  where id = p_outbox_id
    and status = 'processing'
    and locked_by = nullif(trim(p_worker_id), '');

  return found;
end;
$$;

revoke all on function public.complete_communication_outbox(uuid, text, text) from public;
grant execute on function public.complete_communication_outbox(uuid, text, text) to service_role;

create or replace function public.fail_communication_outbox(
  p_outbox_id uuid,
  p_worker_id text,
  p_failure_reason text,
  p_retry_after_seconds int default 300
)
returns boolean
language plpgsql
security invoker
set search_path = public, app_private
as $$
begin
  if current_user <> 'service_role' then
    raise exception 'Only the service role can fail communication jobs';
  end if;

  update public.communication_outbox
  set status = case when attempts >= max_attempts then 'failed' else 'pending' end,
      failure_reason = left(coalesce(p_failure_reason, 'Delivery attempt failed.'), 2000),
      next_attempt_at = case
        when attempts >= max_attempts then null
        else now() + make_interval(secs => greatest(30, least(coalesce(p_retry_after_seconds, 300), 86400)))
      end,
      locked_at = null,
      locked_by = null
  where id = p_outbox_id
    and status = 'processing'
    and locked_by = nullif(trim(p_worker_id), '');

  return found;
end;
$$;

revoke all on function public.fail_communication_outbox(uuid, text, text, int) from public;
grant execute on function public.fail_communication_outbox(uuid, text, text, int) to service_role;
