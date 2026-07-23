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

insert into public.canteen_categories (id, name, display_order, is_active)
values ('00000000-0000-4000-8000-000000000215', 'Smoke Canteen', 0, true);

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

select check_name, passed, detail from smoke_results order by check_name;

rollback;
