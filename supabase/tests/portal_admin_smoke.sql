begin;

create temp table smoke_results (check_name text, passed boolean, detail text);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
('00000000-0000-4000-8000-000000000211','00000000-0000-0000-0000-000000000000','authenticated','authenticated','portal-admin-test@example.invalid','',now(),'{"provider":"email","providers":["email"]}'::jsonb,'{"full_name":"Portal Admin Test"}'::jsonb,now(),now()),
('00000000-0000-4000-8000-000000000212','00000000-0000-0000-0000-000000000000','authenticated','authenticated','portal-user-test@example.invalid','',now(),'{"provider":"email","providers":["email"]}'::jsonb,'{"full_name":"Portal User Test","role":"super_administrator"}'::jsonb,now(),now());

insert into public.seasons (id, name, year, starts_on, ends_on, status)
values ('00000000-0000-4000-8000-000000000213', 'Smoke Test Season', 2027, '2027-01-01', '2027-12-31', 'active');

insert into public.teams (id, season_id, name, division, status)
values ('00000000-0000-4000-8000-000000000214', '00000000-0000-4000-8000-000000000213', 'Smoke Test Team', 'Blue', 'active');

select app_private.bootstrap_super_admin('00000000-0000-4000-8000-000000000211', 'Rollback smoke test bootstrap for portal admin RPCs');

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000212', true);

insert into smoke_results
select 'general user cannot assign roles', not public.has_permission('roles.assign'), 'roles.assign false';

insert into smoke_results
select 'metadata cannot create super admin',
  not exists(
    select 1
    from public.user_role_assignments ura
    join public.roles r on r.id = ura.role_id
    where ura.user_id = '00000000-0000-4000-8000-000000000212'
      and r.key = 'super_administrator'
  ),
  'raw_user_meta_data ignored';

insert into smoke_results
select 'role request creation is disabled',
  not has_function_privilege('authenticated', 'public.request_role(uuid, uuid, uuid, text, text, text)', 'execute'),
  'authenticated cannot execute request_role';

do $$
begin
  perform public.assign_user_role('00000000-0000-4000-8000-000000000212', (select id from public.roles where key = 'coach'), '00000000-0000-4000-8000-000000000214', '00000000-0000-4000-8000-000000000213', now(), null, 'General user should not be able to assign roles');
  insert into smoke_results values ('general user cannot assign via RPC', false, 'unexpected success');
exception when others then
  insert into smoke_results values ('general user cannot assign via RPC', true, sqlerrm);
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000211', true);

select public.assign_user_role(
  '00000000-0000-4000-8000-000000000212',
  (select id from public.roles where key = 'coach'),
  '00000000-0000-4000-8000-000000000214',
  '00000000-0000-4000-8000-000000000213',
  now(),
  now() + interval '30 days',
  'Assign coach role during rollback smoke test'
);

insert into smoke_results
select 'super admin can assign scoped coach role',
  exists(
    select 1
    from public.user_role_assignments ura
    join public.roles r on r.id = ura.role_id
    where ura.user_id = '00000000-0000-4000-8000-000000000212'
      and r.key = 'coach'
      and ura.team_id = '00000000-0000-4000-8000-000000000214'
  ),
  'assignment inserted';

insert into smoke_results
select 'assigned team appears in member team rpc',
  exists (
    select 1
    from public.member_team_ids()
    where team_id = '00000000-0000-4000-8000-000000000214'
      and relationship = 'role'
  ),
  'member_team_ids includes assigned team';

insert into public.team_staff (team_id, user_id, staff_role, status)
values ('00000000-0000-4000-8000-000000000214', '00000000-0000-4000-8000-000000000212', 'team_manager', 'active');

insert into smoke_results
select 'team staff can manage team operations',
  app_private.can_manage_team_operations('00000000-0000-4000-8000-000000000214'),
  'team manager assignment permits team posts and reports';

insert into public.match_reports (team_id, author_id, final_score_for, final_score_against, result, highlights, status)
values ('00000000-0000-4000-8000-000000000214', '00000000-0000-4000-8000-000000000212', 2, 1, 'win', 'Smoke test report', 'submitted');

insert into smoke_results
select 'team staff report can be saved',
  exists (
    select 1
    from public.match_reports
    where team_id = '00000000-0000-4000-8000-000000000214'
      and author_id = '00000000-0000-4000-8000-000000000212'
      and status = 'submitted'
  ),
  'match report inserted for active team staff';

insert into public.volunteer_opportunities (id, title, description, opportunity_type, status)
values ('00000000-0000-4000-8000-000000000220', 'Smoke Volunteer Gate', 'Smoke volunteer roster', 'match_day', 'active');

insert into public.volunteer_shifts (id, opportunity_id, starts_at, ends_at, capacity, status)
values (
  '00000000-0000-4000-8000-000000000221',
  '00000000-0000-4000-8000-000000000220',
  now() + interval '1 hour',
  now() + interval '3 hours',
  1,
  'open'
);

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000212', true);

with requested as (
  select *
  from public.request_volunteer_shift('00000000-0000-4000-8000-000000000221')
)
insert into smoke_results
select 'member can request open volunteer shift',
  requested.assignment_status = 'assigned'
  and requested.shift_status = 'filled'
  and exists (
    select 1
    from public.volunteer_assignments va
    where va.id = requested.assignment_id
      and va.user_id = '00000000-0000-4000-8000-000000000212'
      and va.status = 'assigned'
  ),
  'capacity-aware RPC assigns member and fills one-person shift'
from requested;

with requested_again as (
  select *
  from public.request_volunteer_shift('00000000-0000-4000-8000-000000000221')
)
insert into smoke_results
select 'duplicate volunteer request is idempotent',
  requested_again.assignment_status = 'assigned'
  and (
    select count(*)
    from public.volunteer_assignments
    where shift_id = '00000000-0000-4000-8000-000000000221'
      and user_id = '00000000-0000-4000-8000-000000000212'
  ) = 1,
  'repeat signup returns existing assignment'
from requested_again;

with checked_in as (
  select *
  from public.update_volunteer_assignment(
    (
      select id
      from public.volunteer_assignments
      where shift_id = '00000000-0000-4000-8000-000000000221'
        and user_id = '00000000-0000-4000-8000-000000000212'
      limit 1
    ),
    'checked_in',
    'Smoke member check-in'
  )
)
insert into smoke_results
select 'member can check in volunteer assignment',
  checked_in.assignment_status = 'checked_in'
  and exists (
    select 1
    from public.volunteer_assignments
    where id = checked_in.assignment_id
      and checked_in_at is not null
  ),
  'check-in timestamp recorded'
from checked_in;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000211', true);

with completed_shift as (
  select *
  from public.update_volunteer_shift_status(
    '00000000-0000-4000-8000-000000000221',
    'completed',
    'Smoke shift completed'
  )
)
insert into smoke_results
select 'volunteer coordinator can complete shift',
  completed_shift.shift_status = 'completed'
  and completed_shift.affected_assignments = 1
  and exists (
    select 1
    from public.volunteer_assignments
    where shift_id = completed_shift.shift_id
      and status = 'completed'
      and completed_at is not null
  ),
  'shift completion completes active assignment'
from completed_shift;

insert into public.coaching_resources (
  title,
  resource_type,
  summary,
  body,
  age_group_tags,
  skill_level_tags,
  duration_minutes,
  equipment_required,
  visibility,
  status,
  created_by
)
values (
  'Smoke Pressing Drill',
  'drill',
  'Smoke coaching resource',
  '{"type":"plain_text","text":"Set up a compact pressing grid and rotate defenders."}'::jsonb,
  array['U12','Seniors'],
  array['intermediate'],
  20,
  array['cones','bibs'],
  'coaches',
  'published',
  '00000000-0000-4000-8000-000000000211'
);

insert into smoke_results
select 'coaching resource publish metadata is prepared',
  exists (
    select 1
    from public.coaching_resources cr
    where cr.title = 'Smoke Pressing Drill'
      and cr.slug = 'smoke-pressing-drill'
      and cr.published_at is not null
      and cr.age_group_tags @> array['U12']
      and cr.equipment_required @> array['cones']
  ),
  'published coaching resources receive slug and searchable tags';

insert into public.content_articles (
  title,
  slug,
  summary,
  body,
  category,
  workflow_status,
  tags,
  author_id
)
values (
  'Smoke Public Article',
  '',
  'Smoke public publishing summary',
  '{"type":"plain_text","text":"Public article body for database-backed publishing."}'::jsonb,
  'Club news',
  'published',
  array['smoke','public'],
  '00000000-0000-4000-8000-000000000211'
);

insert into public.club_announcements (title, message, audience, priority, status, created_by)
values ('Smoke Public Announcement', 'Smoke public announcement body', 'public', 1, 'published', '00000000-0000-4000-8000-000000000211');

insert into public.sponsors (name, tier, description, website_url, display_locations, display_priority, status)
values ('Smoke Sponsor', 'Community', 'Smoke sponsor record', 'https://example.invalid', array['homepage','sponsors'], 1, 'active');

insert into smoke_results
select 'public content publishing metadata is prepared',
  exists (
    select 1
    from public.content_articles ca
    where ca.title = 'Smoke Public Article'
      and ca.slug = 'smoke-public-article'
      and ca.workflow_status = 'published'
      and ca.publish_at is not null
      and ca.tags @> array['public']
  )
  and exists (
    select 1
    from public.club_announcements ca
    where ca.title = 'Smoke Public Announcement'
      and ca.status = 'published'
      and ca.audience = 'public'
  )
  and exists (
    select 1
    from public.sponsors s
    where s.name = 'Smoke Sponsor'
      and s.status = 'active'
      and s.display_locations @> array['homepage']
  ),
  'public article, announcement and sponsor rows are ready for runtime rendering';

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000212', true);

with ensured as (
  select public.ensure_wallet_account(null, null, 'user') as wallet_id
)
insert into smoke_results
select 'member can create wallet account',
  exists (
    select 1
    from public.wallet_accounts wa
    where wa.id = ensured.wallet_id
      and wa.owner_id = '00000000-0000-4000-8000-000000000212'
      and wa.account_type = 'user'
      and wa.status = 'active'
  ),
  'wallet account ensured for member'
from ensured;

with top_up as (
  select *
  from public.create_wallet_top_up(
    (
      select id
      from public.wallet_accounts
      where owner_id = '00000000-0000-4000-8000-000000000212'
      limit 1
    ),
    1000,
    'manual',
    'smoke-wallet-top-up'
  )
)
insert into smoke_results
select 'member can create wallet top-up request',
  top_up.payment_status = 'created'
  and top_up.amount_cents = 1000
  and exists (
    select 1
    from public.payments p
    where p.id = top_up.payment_id
      and p.payer_id = '00000000-0000-4000-8000-000000000212'
      and p.metadata->>'purpose' = 'wallet_top_up'
  ),
  'payment request created with wallet metadata'
from top_up;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000211', true);

with settled as (
  select *
  from public.settle_wallet_top_up(
    (
      select id
      from public.payments
      where idempotency_key = 'smoke-wallet-top-up'
      limit 1
    ),
    'succeeded',
    'SMOKE-POS-1',
    'Smoke settlement'
  )
)
insert into smoke_results
select 'treasurer can settle wallet top-up',
  settled.payment_status = 'succeeded'
  and settled.ledger_entry_id is not null
  and exists (
    select 1
    from public.wallet_balances wb
    join public.wallet_accounts wa on wa.id = wb.wallet_account_id
    where wa.owner_id = '00000000-0000-4000-8000-000000000212'
      and wb.balance_cents = 1000
  ),
  'settled top-up credits wallet ledger'
from settled;

with adjusted as (
  select public.adjust_wallet_balance(
    (
      select id
      from public.wallet_accounts
      where owner_id = '00000000-0000-4000-8000-000000000212'
      limit 1
    ),
    250,
    'debit',
    'manual_adjustment',
    'Smoke debit adjustment',
    'smoke-wallet-debit',
    '00000000-0000-4000-8000-000000000212'
  ) as entry_id
)
insert into smoke_results
select 'wallet adjustment debits available balance',
  exists (
    select 1
    from public.wallet_ledger_entries wle
    join public.wallet_balances wb on wb.wallet_account_id = wle.wallet_account_id
    where wle.id = adjusted.entry_id
      and wle.direction = 'debit'
      and wb.balance_cents = 750
  ),
  'manual debit adjustment recorded'
from adjusted;

with reversed_wallet_entry as (
  select public.reverse_wallet_ledger_entry(
    (
      select id
      from public.wallet_ledger_entries
      where idempotency_key = 'smoke-wallet-debit'
      limit 1
    ),
    'Smoke debit reversal'
  ) as reversal_id
)
insert into smoke_results
select 'wallet ledger reversal restores balance',
  exists (
    select 1
    from public.wallet_ledger_entries reversal
    join public.wallet_balances wb on wb.wallet_account_id = reversal.wallet_account_id
    where reversal.id = reversed_wallet_entry.reversal_id
      and reversal.direction = 'credit'
      and reversal.reversal_of = (
        select id
        from public.wallet_ledger_entries
        where idempotency_key = 'smoke-wallet-debit'
        limit 1
      )
      and wb.balance_cents = 1000
  ),
  'reversal credit links back to original debit'
from reversed_wallet_entry;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000212', true);

with provider_top_up as (
  select *
  from public.create_wallet_top_up(
    (
      select id
      from public.wallet_accounts
      where owner_id = '00000000-0000-4000-8000-000000000212'
      limit 1
    ),
    1200,
    'stripe',
    'smoke-provider-top-up'
  )
)
insert into smoke_results
select 'member can create provider-backed wallet top-up',
  provider_top_up.payment_status = 'requires_action'
  and provider_top_up.amount_cents = 1200,
  'provider top-up waits for webhook settlement'
from provider_top_up;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000211', true);

with processed as (
  select *
  from public.process_payment_webhook(
    'stripe',
    'evt_smoke_wallet_top_up',
    'payment.succeeded',
    'pi_smoke_wallet_top_up',
    (
      select id
      from public.payments
      where idempotency_key = 'smoke-provider-top-up'
      limit 1
    ),
    'succeeded',
    '{"source":"smoke"}'::jsonb
  )
)
insert into smoke_results
select 'payment webhook settles provider wallet top-up',
  processed.event_status = 'processed'
  and processed.payment_status = 'succeeded'
  and exists (
    select 1
    from public.wallet_balances wb
    join public.wallet_accounts wa on wa.id = wb.wallet_account_id
    where wa.owner_id = '00000000-0000-4000-8000-000000000212'
      and wb.balance_cents = 2200
  ),
  'webhook processor credits wallet once'
from processed;

with replayed as (
  select *
  from public.process_payment_webhook(
    'stripe',
    'evt_smoke_wallet_top_up',
    'payment.succeeded',
    'pi_smoke_wallet_top_up',
    (
      select id
      from public.payments
      where idempotency_key = 'smoke-provider-top-up'
      limit 1
    ),
    'succeeded',
    '{"source":"smoke","replayed":true}'::jsonb
  )
)
insert into smoke_results
select 'payment webhook replay is idempotent',
  replayed.already_processed
  and exists (
    select 1
    from public.wallet_balances wb
    join public.wallet_accounts wa on wa.id = wb.wallet_account_id
    where wa.owner_id = '00000000-0000-4000-8000-000000000212'
      and wb.balance_cents = 2200
  ),
  'duplicate provider event does not duplicate wallet credit'
from replayed;

insert into public.canteen_categories (id, name, display_order, is_active)
values ('00000000-0000-4000-8000-000000000215', 'Smoke Canteen', 0, true);

insert into public.canteen_venues (id, name, is_active)
values ('00000000-0000-4000-8000-000000000219', 'Smoke Canteen Window', true);

insert into public.canteen_products (
  id,
  category_id,
  name,
  price_cents,
  fulfilment_type,
  stock_quantity,
  low_stock_threshold,
  voucher_valid_days,
  is_active,
  is_sold_out
)
values (
  '00000000-0000-4000-8000-000000000216',
  '00000000-0000-4000-8000-000000000215',
  'Smoke Voucher Snack',
  250,
  'item_voucher',
  6,
  2,
  7,
  true,
  false
);

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000212', true);

do $$
begin
  perform *
  from public.create_canteen_order(
    '00000000-0000-4000-8000-000000000216',
    null,
    null,
    2,
    null,
    'Smoke test order'
  );
end $$;

insert into smoke_results
select 'member can create stock-backed canteen voucher order',
  exists (
    select 1
    from public.canteen_orders co
    join public.canteen_order_items coi on coi.order_id = co.id
    where co.customer_id = '00000000-0000-4000-8000-000000000212'
      and co.payment_status = 'unpaid'
      and co.order_status = 'accepted'
      and co.pickup_code like 'GEORDER:%'
      and coi.product_id = '00000000-0000-4000-8000-000000000216'
      and coi.fulfilment_type_snapshot = 'item_voucher'
  ),
  'member order inserted with voucher fulfilment snapshot';

insert into smoke_results
select 'canteen order reserves stock',
  stock_quantity = 4,
  'stock decremented from 6 to 4'
from public.canteen_products
where id = '00000000-0000-4000-8000-000000000216';

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000211', true);

with paid as (
  select *
  from public.update_canteen_order_state(
    (
      select id
      from public.canteen_orders
      where customer_id = '00000000-0000-4000-8000-000000000212'
        and order_number like 'GE-%'
      order by created_at desc
      limit 1
    ),
    null,
    'paid',
    'Smoke test payment'
  )
)
insert into smoke_results
select 'paid canteen voucher order issues wallet voucher',
  paid.issued_vouchers = 1
  and exists (
    select 1
    from public.canteen_order_items coi
    join public.voucher_issuances vi on vi.id = coi.voucher_issuance_id
    where coi.order_id = paid.order_id
      and vi.beneficiary_id = '00000000-0000-4000-8000-000000000212'
      and vi.voucher_type = 'specific_product'
      and vi.remaining_value_cents = 500
      and vi.redemption_limit = 2
      and vi.status = 'active'
  ),
  'paid item_voucher order creates a wallet voucher'
from paid;

with redeemed as (
  select *
  from public.redeem_voucher(
    (
      select vi.redemption_code
      from public.canteen_order_items coi
      join public.voucher_issuances vi on vi.id = coi.voucher_issuance_id
      where coi.product_id = '00000000-0000-4000-8000-000000000216'
      order by vi.created_at desc
      limit 1
    ),
    '00000000-0000-4000-8000-000000000219',
    250,
    null,
    'Smoke test scanner'
  )
)
insert into smoke_results
select 'canteen worker can redeem wallet voucher',
  redeemed.remaining_value_cents = 250
  and exists (
    select 1
    from public.voucher_redemptions vr
    where vr.id = redeemed.redemption_id
      and vr.amount_cents = 250
      and vr.status = 'completed'
  ),
  'voucher redemption debits remaining balance'
from redeemed;

with reversed as (
  select public.reverse_voucher_redemption(
    (
      select vr.id
      from public.voucher_redemptions vr
      join public.voucher_issuances vi on vi.id = vr.voucher_id
      where vi.beneficiary_id = '00000000-0000-4000-8000-000000000212'
      order by vr.created_at desc
      limit 1
    ),
    'Smoke test reversal'
  ) as reversal_id
)
insert into smoke_results
select 'voucher redemption reversal restores voucher balance',
  exists (
    select 1
    from public.voucher_reversals vrev
    join public.voucher_redemptions vr on vr.id = vrev.redemption_id
    join public.voucher_issuances vi on vi.id = vr.voucher_id
    where vrev.id = reversed.reversal_id
      and vrev.reason = 'Smoke test reversal'
      and vr.status = 'reversed'
      and vi.remaining_value_cents = 500
      and vi.redemption_count = 0
      and vi.status = 'active'
  ),
  'voucher reversal restores amount and writes reversal audit row'
from reversed;

insert into public.merchandise_products (id, name, category, status)
values ('00000000-0000-4000-8000-000000000217', 'Smoke Hoodie', 'Smoke Shop', 'active');

insert into public.merchandise_variants (
  id,
  product_id,
  sku,
  size,
  colour,
  price_cents,
  stock_quantity,
  low_stock_threshold,
  is_active
)
values (
  '00000000-0000-4000-8000-000000000218',
  '00000000-0000-4000-8000-000000000217',
  'SMOKE-HOODIE-M',
  'M',
  'Green',
  4500,
  5,
  1,
  true
);

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000212', true);

do $$
begin
  perform *
  from public.create_merchandise_order(
    '00000000-0000-4000-8000-000000000218',
    2,
    'pickup',
    'Smoke merchandise order'
  );
end $$;

insert into smoke_results
select 'member can create stock-backed merchandise order',
  exists (
    select 1
    from public.merchandise_orders mo
    join public.merchandise_order_items moi on moi.order_id = mo.id
    where mo.customer_id = '00000000-0000-4000-8000-000000000212'
      and mo.status = 'awaiting_payment'
      and mo.total_cents = 9000
      and moi.variant_id = '00000000-0000-4000-8000-000000000218'
      and moi.quantity = 2
      and moi.line_total_cents = 9000
  ),
  'member order inserted with line item snapshot';

insert into smoke_results
select 'merchandise order reserves stock',
  stock_quantity = 3,
  'stock decremented from 5 to 3'
from public.merchandise_variants
where id = '00000000-0000-4000-8000-000000000218';

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000211', true);

with moved as (
  select *
  from public.update_merchandise_order_state(
    (
      select id
      from public.merchandise_orders
      where customer_id = '00000000-0000-4000-8000-000000000212'
        and order_number like 'GM-%'
      order by created_at desc
      limit 1
    ),
    'paid',
    'Smoke test payment'
  )
)
insert into smoke_results
select 'merchandise manager can mark order paid',
  moved.new_status = 'paid'
  and exists (
    select 1
    from public.merchandise_order_status_history
    where order_id = moved.order_id
      and old_status = 'awaiting_payment'
      and new_status = 'paid'
  ),
  'status RPC records merchandise history'
from moved;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000211', true);

insert into public.notification_preferences (user_id, channel, category, enabled)
values
  ('00000000-0000-4000-8000-000000000212', 'email', 'commerce', true),
  ('00000000-0000-4000-8000-000000000212', 'sms', 'commerce', false),
  ('00000000-0000-4000-8000-000000000212', 'in_app', 'commerce', true)
on conflict (user_id, channel, category)
do update set enabled = excluded.enabled;

do $$
begin
  perform *
  from public.enqueue_admin_notification(
    '00000000-0000-4000-8000-000000000212',
    'Smoke order update',
    'Your smoke order is ready.',
    'commerce',
    array['in_app','email','sms'],
    'admin_message',
    '{"smoke":true}'::jsonb,
    'canteen_order',
    '00000000-0000-4000-8000-000000000214',
    '/portal/canteen/',
    'smoke-commerce-ready',
    now()
  );

  perform *
  from public.enqueue_admin_notification(
    '00000000-0000-4000-8000-000000000212',
    'Smoke order update',
    'Your smoke order is still ready.',
    'commerce',
    array['in_app','email','sms'],
    'admin_message',
    '{"smoke":true,"updated":true}'::jsonb,
    'canteen_order',
    '00000000-0000-4000-8000-000000000214',
    '/portal/canteen/',
    'smoke-commerce-ready',
    now()
  );
end $$;

insert into smoke_results
select 'notification preferences queue only enabled channels',
  exists (
    select 1
    from public.notifications
    where recipient_id = '00000000-0000-4000-8000-000000000212'
      and dedupe_key = 'smoke-commerce-ready'
      and body = 'Your smoke order is still ready.'
      and action_url = '/portal/canteen/'
  )
  and exists (
    select 1
    from public.communication_outbox
    where recipient_id = '00000000-0000-4000-8000-000000000212'
      and dedupe_key = 'smoke-commerce-ready:email'
      and channel = 'email'
      and status = 'pending'
  )
  and not exists (
    select 1
    from public.communication_outbox
    where recipient_id = '00000000-0000-4000-8000-000000000212'
      and dedupe_key = 'smoke-commerce-ready:sms'
  ),
  'in-app notice deduped, email queued, sms suppressed by preference';

select check_name, passed, detail from smoke_results order by check_name;

rollback;
