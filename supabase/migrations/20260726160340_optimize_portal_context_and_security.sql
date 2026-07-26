-- Portal request consolidation, least-privilege RPC grants, dashboard aggregation,
-- RLS init-plan improvements, and query-driven relationship indexes.

create or replace function public.has_any_permission(
  required_keys text[],
  target_team_id uuid default null,
  target_season_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, app_private, extensions
as $$
  select
    (select auth.uid()) is not null
    and coalesce(cardinality(required_keys), 0) > 0
    and not exists (
      select 1
      from public.managed_child_accounts child
      where child.child_user_id = (select auth.uid())
    )
    and exists (
      select 1
      from public.user_role_assignments assignment
      join public.role_permissions role_permission
        on role_permission.role_id = assignment.role_id
      join public.permissions permission
        on permission.id = role_permission.permission_id
      where assignment.user_id = (select auth.uid())
        and assignment.status = 'active'
        and assignment.starts_at <= now()
        and (assignment.ends_at is null or assignment.ends_at > now())
        and (permission.key = '*' or permission.key = any(required_keys))
        and (
          target_team_id is null
          or assignment.team_id is null
          or assignment.team_id = target_team_id
        )
        and (
          target_season_id is null
          or assignment.season_id is null
          or assignment.season_id = target_season_id
        )
    );
$$;

revoke all on function public.has_any_permission(text[], uuid, uuid) from public, anon;
grant execute on function public.has_any_permission(text[], uuid, uuid) to authenticated, service_role;

create or replace function public.get_portal_context()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, app_private, extensions
as $$
  with caller as (
    select (select auth.uid()) as user_id
  ),
  profile_data as (
    select jsonb_build_object(
      'id', profile.id,
      'full_name', profile.full_name,
      'preferred_name', profile.preferred_name,
      'mobile', profile.mobile,
      'relationship_to_club', profile.relationship_to_club,
      'emergency_contact_name', profile.emergency_contact_name,
      'emergency_contact_phone', profile.emergency_contact_phone,
      'communication_email', profile.communication_email,
      'communication_sms', profile.communication_sms,
      'terms_accepted_at', profile.terms_accepted_at,
      'privacy_accepted_at', profile.privacy_accepted_at,
      'onboarding_completed_at', profile.onboarding_completed_at,
      'account_status', profile.account_status,
      'created_at', profile.created_at,
      'updated_at', profile.updated_at,
      'email', profile.email,
      'date_of_birth', profile.date_of_birth,
      'public_photo_object_key', profile.public_photo_object_key,
      'public_photo_consent', profile.public_photo_consent,
      'public_photo_updated_at', profile.public_photo_updated_at
    ) as profile
    from public.profiles profile
    join caller on caller.user_id = profile.id
  ),
  active_assignments as (
    select
      assignment.id,
      assignment.role_id,
      assignment.team_id,
      assignment.season_id,
      assignment.status,
      assignment.starts_at,
      assignment.ends_at,
      assignment.reason,
      assignment.created_at
    from public.user_role_assignments assignment
    join caller on caller.user_id = assignment.user_id
    where assignment.status = 'active'
      and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
  ),
  assignment_data as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', assignment.id,
          'status', assignment.status,
          'starts_at', assignment.starts_at,
          'ends_at', assignment.ends_at,
          'reason', assignment.reason,
          'role', jsonb_build_object(
            'id', role.id,
            'key', role.key,
            'name', role.name,
            'description', role.description,
            'is_sensitive', role.is_sensitive
          ),
          'team', case when team.id is null then null else jsonb_build_object(
            'id', team.id,
            'name', team.name
          ) end,
          'season', case when season.id is null then null else jsonb_build_object(
            'id', season.id,
            'name', season.name
          ) end
        )
        order by assignment.created_at desc
      ),
      '[]'::jsonb
    ) as assignments
    from active_assignments assignment
    join public.roles role on role.id = assignment.role_id
    left join public.teams team on team.id = assignment.team_id
    left join public.seasons season on season.id = assignment.season_id
  ),
  permission_data as (
    select coalesce(
      array_agg(distinct permission.key order by permission.key),
      array[]::text[]
    ) as permission_keys
    from active_assignments assignment
    join public.role_permissions role_permission
      on role_permission.role_id = assignment.role_id
    join public.permissions permission
      on permission.id = role_permission.permission_id
  ),
  notification_data as (
    select count(*)::integer as unread_count
    from public.notifications notification
    join caller on caller.user_id = notification.recipient_id
    where notification.read_at is null
  ),
  child_data as (
    select
      exists (
        select 1
        from public.managed_child_accounts child
        join caller on caller.user_id = child.child_user_id
      ) as is_child_account,
      coalesce((
        select child.login_disabled
        from public.managed_child_accounts child
        join caller on caller.user_id = child.child_user_id
        limit 1
      ), false) as login_disabled
  )
  select case
    when caller.user_id is null then null
    else jsonb_build_object(
      'user_id', caller.user_id,
      'profile', profile_data.profile,
      'role_assignments', assignment_data.assignments,
      'permission_keys', to_jsonb(permission_data.permission_keys),
      'is_super_admin', '*' = any(permission_data.permission_keys),
      'unread_notifications', notification_data.unread_count,
      'is_child_account', child_data.is_child_account,
      'child_login_disabled', child_data.login_disabled
    )
  end
  from caller
  left join profile_data on true
  cross join assignment_data
  cross join permission_data
  cross join notification_data
  cross join child_data;
$$;

revoke all on function public.get_portal_context() from public, anon;
grant execute on function public.get_portal_context() to authenticated, service_role;

-- Replace the dashboard's fifteen HTTP count requests with one authorised
-- transactional snapshot. The permission list mirrors the existing admin shell.
create or replace function public.admin_dashboard_summary()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, app_private, extensions
as $$
  select case
    when not public.has_any_permission(array[
      'users.read', 'users.manage', 'roles.read', 'roles.assign', 'roles.review',
      'team_access.review', 'team_members.manage', 'club_structure.manage',
      'families.manage', 'players.manage', 'teams.manage', 'team_posts.create',
      'team_posts.moderate', 'match_reports.read', 'match_reports.review',
      'content.manage', 'social_profiles.view', 'social_profiles.manage',
      'social_posts.view', 'social_posts.manage', 'sponsors.manage',
      'sponsors.view', 'canteen.manage', 'canteen.orders.manage',
      'canteen.vouchers.manage', 'canteen.vouchers.reverse', 'wallet.read',
      'wallet.adjust', 'wallet.vouchers.manage', 'finance.read',
      'merchandise.manage', 'merchandise.store_access', 'shop.products.view',
      'shop.products.manage', 'shop.orders.view', 'shop.orders.manage',
      'shop.canteen.scan', 'shop.canteen.redeem', 'shop.merchandise.fulfil',
      'events.manage', 'events.orders.read', 'events.tickets.scan',
      'events.tickets.redeem', 'volunteers.manage', 'communications.manage',
      'files.manage', 'coaching_resources.manage', 'children.manage'
    ]::text[]) then '{}'::jsonb
    else jsonb_build_object(
      'total_users', (select count(*) from public.profiles),
      'new_users', (select count(*) from public.profiles where created_at >= now() - interval '30 days'),
      'active_players', (select count(*) from public.player_records where registration_status = 'registered'),
      'active_families', (select count(*) from public.families),
      'teams', (select count(*) from public.teams where status = 'active'),
      'active_volunteers', (select count(*) from public.volunteer_assignments where status in ('assigned', 'confirmed')),
      'upcoming_events', (select count(*) from public.club_events where status = 'active' and starts_at >= now()),
      'event_registrations', (select count(*) from public.event_registrations where status in ('interest', 'confirmed', 'waitlisted')),
      'canteen_orders_today', (select count(*) from public.canteen_orders where created_at >= now() - interval '24 hours'),
      'canteen_orders_open', (select count(*) from public.canteen_orders where order_status in ('new', 'accepted', 'preparing')),
      'canteen_orders_ready', (select count(*) from public.canteen_orders where order_status = 'ready_for_pickup'),
      'team_access_requests', (select count(*) from public.team_access_requests where status = 'pending'),
      'active_vouchers', (select count(*) from public.voucher_issuances where status = 'active'),
      'expiring_vouchers', (select count(*) from public.voucher_issuances where status = 'active' and expires_at <= now() + interval '14 days'),
      'active_news', (select count(*) from public.content_articles where workflow_status = 'active')
    )
  end;
$$;

revoke all on function public.admin_dashboard_summary() from public, anon;
grant execute on function public.admin_dashboard_summary() to authenticated, service_role;

-- Public permission lookup is authenticated-only. Anonymous requests do not
-- need a callable RPC which always resolves to false.
revoke all on function public.has_permission(text, uuid, uuid) from public, anon;
grant execute on function public.has_permission(text, uuid, uuid) to authenticated, service_role;

-- Correct the explicit anonymous grants currently present on privileged RPCs.
-- User-facing RPCs retain authenticated access and their existing internal
-- ownership/permission checks; webhook processing is service-only.
revoke all on function public.adjust_wallet_balance(uuid, integer, text, text, text, text, uuid) from public, anon;
grant execute on function public.adjust_wallet_balance(uuid, integer, text, text, text, text, uuid) to authenticated, service_role;
alter function public.adjust_wallet_balance(uuid, integer, text, text, text, text, uuid)
  set search_path = pg_catalog, public, app_private, extensions;

revoke all on function public.create_wallet_top_up(uuid, integer, text, text) from public, anon;
grant execute on function public.create_wallet_top_up(uuid, integer, text, text) to authenticated, service_role;
alter function public.create_wallet_top_up(uuid, integer, text, text)
  set search_path = pg_catalog, public, app_private, extensions;

revoke all on function public.enqueue_admin_notification(uuid, text, text, text, text[], text, jsonb, text, uuid, text, text, timestamptz) from public, anon;
grant execute on function public.enqueue_admin_notification(uuid, text, text, text, text[], text, jsonb, text, uuid, text, text, timestamptz) to authenticated, service_role;
alter function public.enqueue_admin_notification(uuid, text, text, text, text[], text, jsonb, text, uuid, text, text, timestamptz)
  set search_path = pg_catalog, public, app_private, extensions;

revoke all on function public.ensure_wallet_account(uuid, uuid, text) from public, anon;
grant execute on function public.ensure_wallet_account(uuid, uuid, text) to authenticated, service_role;
alter function public.ensure_wallet_account(uuid, uuid, text)
  set search_path = pg_catalog, public, app_private, extensions;

revoke all on function public.process_payment_webhook(text, text, text, text, uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.process_payment_webhook(text, text, text, text, uuid, text, jsonb) to service_role;
alter function public.process_payment_webhook(text, text, text, text, uuid, text, jsonb)
  set search_path = pg_catalog, public, app_private, extensions;

revoke all on function public.process_wallet_qr_purchase(text, integer, text, text) from public, anon;
grant execute on function public.process_wallet_qr_purchase(text, integer, text, text) to authenticated, service_role;
alter function public.process_wallet_qr_purchase(text, integer, text, text)
  set search_path = pg_catalog, public, app_private, extensions;

revoke all on function public.request_team_access(uuid, text, text) from public, anon;
grant execute on function public.request_team_access(uuid, text, text) to authenticated, service_role;
alter function public.request_team_access(uuid, text, text)
  set search_path = pg_catalog, public, app_private, extensions;

revoke all on function public.request_volunteer_shift(uuid) from public, anon;
grant execute on function public.request_volunteer_shift(uuid) to authenticated, service_role;
alter function public.request_volunteer_shift(uuid)
  set search_path = pg_catalog, public, app_private, extensions;

revoke all on function public.reverse_wallet_ledger_entry(uuid, text) from public, anon;
grant execute on function public.reverse_wallet_ledger_entry(uuid, text) to authenticated, service_role;
alter function public.reverse_wallet_ledger_entry(uuid, text)
  set search_path = pg_catalog, public, app_private, extensions;

revoke all on function public.review_team_access_request(uuid, text, text) from public, anon;
grant execute on function public.review_team_access_request(uuid, text, text) to authenticated, service_role;
alter function public.review_team_access_request(uuid, text, text)
  set search_path = pg_catalog, public, app_private, extensions;

revoke all on function public.settle_wallet_top_up(uuid, text, text, text) from public, anon;
grant execute on function public.settle_wallet_top_up(uuid, text, text, text) to authenticated, service_role;
alter function public.settle_wallet_top_up(uuid, text, text, text)
  set search_path = pg_catalog, public, app_private, extensions;

revoke all on function public.update_volunteer_assignment(uuid, text, text) from public, anon;
grant execute on function public.update_volunteer_assignment(uuid, text, text) to authenticated, service_role;
alter function public.update_volunteer_assignment(uuid, text, text)
  set search_path = pg_catalog, public, app_private, extensions;

revoke all on function public.update_volunteer_shift_status(uuid, text, text) from public, anon;
grant execute on function public.update_volunteer_shift_status(uuid, text, text) to authenticated, service_role;
alter function public.update_volunteer_shift_status(uuid, text, text)
  set search_path = pg_catalog, public, app_private, extensions;

-- Convert bare auth.uid() calls in existing public policies to init-plan
-- expressions while preserving each policy's command, roles, and predicates.
do $$
declare
  policy_row record;
  next_using text;
  next_check text;
begin
  for policy_row in
    select
      namespace.nspname as schema_name,
      relation.relname as table_name,
      policy.polname as policy_name,
      policy.polcmd,
      pg_get_expr(policy.polqual, policy.polrelid) as using_expression,
      pg_get_expr(policy.polwithcheck, policy.polrelid) as check_expression
    from pg_policy policy
    join pg_class relation on relation.oid = policy.polrelid
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and (
        coalesce(pg_get_expr(policy.polqual, policy.polrelid), '') ~ 'auth\.uid\(\)'
        or coalesce(pg_get_expr(policy.polwithcheck, policy.polrelid), '') ~ 'auth\.uid\(\)'
      )
  loop
    next_using := case when policy_row.using_expression is null then null else
      replace(policy_row.using_expression, 'auth.uid()', '(select auth.uid())')
    end;
    next_check := case when policy_row.check_expression is null then null else
      replace(policy_row.check_expression, 'auth.uid()', '(select auth.uid())')
    end;

    if next_using is distinct from policy_row.using_expression then
      execute format(
        'alter policy %I on %I.%I using (%s)',
        policy_row.policy_name,
        policy_row.schema_name,
        policy_row.table_name,
        next_using
      );
    end if;
    if next_check is distinct from policy_row.check_expression then
      execute format(
        'alter policy %I on %I.%I with check (%s)',
        policy_row.policy_name,
        policy_row.schema_name,
        policy_row.table_name,
        next_check
      );
    end if;
  end loop;
end;
$$;

-- Query-driven foreign-key and relationship indexes. Tables are currently
-- small, so ordinary CREATE INDEX avoids concurrent migration transaction
-- restrictions without a material lock window.
create index if not exists merchandise_order_items_product_id_idx
  on public.merchandise_order_items(product_id);
create index if not exists merchandise_order_status_history_order_created_idx
  on public.merchandise_order_status_history(order_id, created_at desc);
create index if not exists merchandise_order_status_history_changed_by_idx
  on public.merchandise_order_status_history(changed_by);
create index if not exists canteen_order_items_voucher_issuance_id_idx
  on public.canteen_order_items(voucher_issuance_id);
create index if not exists canteen_orders_completed_by_idx
  on public.canteen_orders(completed_by);
create index if not exists club_event_order_items_ticket_type_id_idx
  on public.club_event_order_items(ticket_type_id);
create index if not exists club_event_orders_event_id_idx
  on public.club_event_orders(event_id);
create index if not exists club_event_orders_payment_id_idx
  on public.club_event_orders(payment_id);
create index if not exists club_event_tickets_order_item_id_idx
  on public.club_event_tickets(order_item_id);
create index if not exists club_event_tickets_redeemed_by_idx
  on public.club_event_tickets(redeemed_by);
create index if not exists managed_child_accounts_manager_family_idx
  on public.managed_child_accounts(manager_user_id, family_id);
create index if not exists family_voucher_assignments_family_id_idx
  on public.family_voucher_assignments(family_id);
create index if not exists family_voucher_assignments_to_user_id_idx
  on public.family_voucher_assignments(to_user_id);
create index if not exists team_posts_author_id_idx
  on public.team_posts(author_id);
create index if not exists team_post_reactions_user_id_idx
  on public.team_post_reactions(user_id);
create index if not exists team_post_reads_user_id_idx
  on public.team_post_reads(user_id);
create index if not exists team_poll_responses_option_id_idx
  on public.team_poll_responses(option_id);
create index if not exists team_poll_responses_user_id_idx
  on public.team_poll_responses(user_id);
create index if not exists voucher_issuances_campaign_id_idx
  on public.voucher_issuances(campaign_id);
create index if not exists voucher_issuances_template_id_idx
  on public.voucher_issuances(template_id);
create index if not exists voucher_issuances_assigned_by_idx
  on public.voucher_issuances(assigned_by);
