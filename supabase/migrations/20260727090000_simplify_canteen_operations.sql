-- Simplified canteen operations: secure completion, ordered categories and batch benefits.

alter table public.canteen_orders
  add column if not exists completed_at timestamptz,
  add column if not exists completed_by uuid references public.profiles(id) on delete set null,
  add column if not exists completion_source text;

create or replace function public.complete_canteen_order(
  target_order_id uuid,
  completion_source text default 'manual'
)
returns table(order_id uuid, order_number text, completed_at timestamptz)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  actor uuid := auth.uid();
  before_row public.canteen_orders%rowtype;
  finished_at timestamptz := now();
begin
  if actor is null then raise exception 'Authentication required'; end if;
  if not (
    app_private.has_permission('canteen.orders.manage')
    or app_private.has_permission('canteen.orders.fulfil')
    or app_private.has_permission('canteen.vouchers.redeem')
  ) then raise exception 'Not authorised'; end if;
  if completion_source not in ('manual', 'qr', 'voucher') then
    raise exception 'Invalid completion source';
  end if;

  select * into before_row
  from public.canteen_orders
  where id = target_order_id
  for update;
  if not found then raise exception 'Order not found'; end if;

  if before_row.order_status = 'collected' then
    return query select before_row.id, before_row.order_number, before_row.completed_at;
    return;
  end if;
  if before_row.order_status not in ('paid', 'accepted', 'preparing', 'ready_for_pickup') then
    raise exception 'This order cannot be completed';
  end if;
  if before_row.payment_status <> 'paid' then
    raise exception 'Payment must be confirmed before completion';
  end if;

  update public.canteen_orders
  set order_status = 'collected',
      completed_at = finished_at,
      completed_by = actor,
      completion_source = complete_canteen_order.completion_source,
      updated_at = finished_at
  where id = target_order_id;

  insert into public.order_status_history(order_id, old_status, new_status, changed_by, reason)
  values (target_order_id, before_row.order_status, 'collected', actor, 'Completed via ' || completion_source);

  insert into public.audit_logs(actor_id, action, entity_type, entity_id, before_state, after_state, reason)
  values (
    actor, 'canteen.order_completed', 'canteen_order', target_order_id,
    jsonb_build_object('order_status', before_row.order_status, 'payment_status', before_row.payment_status),
    jsonb_build_object('order_status', 'collected', 'completed_at', finished_at, 'completed_by', actor),
    completion_source
  );

  return query select before_row.id, before_row.order_number, finished_at;
end;
$$;

create or replace function public.save_canteen_category(
  target_category_id uuid,
  category_name text,
  target_position integer,
  category_active boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  actor uuid := auth.uid();
  saved_id uuid;
  old_row jsonb;
  max_position integer;
begin
  if actor is null or not app_private.has_permission('canteen.manage') then
    raise exception 'Not authorised';
  end if;
  category_name := trim(category_name);
  if length(category_name) < 2 or length(category_name) > 80 then raise exception 'Enter a valid category name'; end if;

  select greatest(count(*)::integer, 0) into max_position from public.canteen_categories;
  target_position := greatest(1, least(coalesce(target_position, max_position + 1), max_position + 1));

  perform 1 from public.canteen_categories for update;
  if target_category_id is null then
    update public.canteen_categories set display_order = display_order + 1 where display_order >= target_position;
    insert into public.canteen_categories(name, display_order, is_active)
    values (category_name, target_position, category_active) returning id into saved_id;
  else
    select to_jsonb(c) into old_row from public.canteen_categories c where id = target_category_id;
    if old_row is null then raise exception 'Category not found'; end if;
    saved_id := target_category_id;
    update public.canteen_categories
    set name = category_name, is_active = category_active, display_order = target_position, updated_at = now()
    where id = target_category_id;
  end if;

  with ranked as (
    select id, row_number() over (
      order by case when id = saved_id then target_position else display_order end, created_at, id
    )::integer as position
    from public.canteen_categories
  )
  update public.canteen_categories c set display_order = ranked.position
  from ranked where ranked.id = c.id;

  insert into public.audit_logs(actor_id, action, entity_type, entity_id, before_state, after_state)
  select actor, 'canteen.category_saved', 'canteen_category', saved_id, old_row, to_jsonb(c)
  from public.canteen_categories c where c.id = saved_id;
  return saved_id;
end;
$$;

create or replace function public.complete_canteen_order_by_code(
  order_code text
)
returns table(order_id uuid, order_number text, completed_at timestamptz)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  matched_order_id uuid;
  normalised_code text := upper(trim(order_code));
begin
  if auth.uid() is null or not (
    app_private.has_permission('canteen.orders.manage')
    or app_private.has_permission('canteen.orders.fulfil')
    or app_private.has_permission('canteen.vouchers.redeem')
  ) then raise exception 'Not authorised'; end if;
  if length(normalised_code) < 8 or length(normalised_code) > 80 then raise exception 'Invalid order code'; end if;

  select id into matched_order_id
  from public.canteen_orders
  where pickup_token_hash = encode(digest(normalised_code, 'sha256'), 'hex')
     or qr_token_hash = encode(digest(normalised_code, 'sha256'), 'hex')
  limit 1;
  if matched_order_id is null then raise exception 'Order code not found'; end if;
  return query select * from public.complete_canteen_order(matched_order_id, 'qr');
end;
$$;

create or replace function public.issue_canteen_benefits(
  member_ids uuid[],
  team_ids uuid[],
  benefit_type text,
  amount_cents integer,
  product_id uuid,
  expires_at timestamptz,
  issue_reason text,
  request_key text
)
returns table(recipient_count integer, wallet_credits integer, item_vouchers integer)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  actor uuid := auth.uid();
  recipient uuid;
  wallet_id uuid;
  item public.canteen_products%rowtype;
  recipients uuid[];
  voucher_id uuid;
  raw_code text;
  credits integer := 0;
  vouchers integer := 0;
begin
  if actor is null or not app_private.has_permission('canteen.vouchers.manage') then
    raise exception 'Not authorised';
  end if;
  if benefit_type not in ('amount', 'item') then raise exception 'Invalid benefit type'; end if;
  if coalesce(array_length(member_ids, 1), 0) + coalesce(array_length(team_ids, 1), 0) = 0 then
    raise exception 'Select at least one member or team';
  end if;
  if nullif(trim(request_key), '') is null then raise exception 'Missing request key'; end if;
  if expires_at is not null and expires_at <= now() then raise exception 'Expiry must be in the future'; end if;

  select coalesce(array_agg(distinct user_id), '{}'::uuid[]) into recipients
  from (
    select unnest(coalesce(member_ids, '{}'::uuid[])) as user_id
    union all
    select pr.user_id
    from public.team_players tp
    join public.player_records pr on pr.id = tp.player_id
    where tp.team_id = any(coalesce(team_ids, '{}'::uuid[])) and tp.status = 'active'
  ) people
  join public.profiles p on p.id = people.user_id and p.account_status = 'active';

  if coalesce(array_length(recipients, 1), 0) = 0 then raise exception 'No active recipients found'; end if;

  if benefit_type = 'item' then
    select * into item from public.canteen_products
    where id = product_id and is_active and not is_sold_out;
    if not found then raise exception 'Select an active, available product'; end if;
  elsif amount_cents is null or amount_cents <= 0 then
    raise exception 'Amount must be greater than zero';
  end if;

  foreach recipient in array recipients loop
    if benefit_type = 'amount' then
      insert into public.wallet_accounts(owner_id, account_type, status)
      values (recipient, 'user', 'active')
      on conflict (owner_id) where account_type = 'user' do update set status = 'active'
      returning id into wallet_id;
      perform app_private.apply_wallet_entry(
        wallet_id, amount_cents, 'credit', 'canteen_benefit',
        'canteen-benefit:' || request_key || ':' || recipient,
        coalesce(nullif(trim(issue_reason), ''), 'Canteen wallet credit'), recipient
      );
      credits := credits + 1;
    else
      raw_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
      insert into public.voucher_issuances(
        token_hash, redemption_code, beneficiary_id, issued_by, issue_reason, voucher_type,
        original_value_cents, remaining_value_cents, allowed_product_ids, valid_from,
        expires_at, status, name, description
      ) values (
        encode(digest(raw_code, 'sha256'), 'hex'), raw_code, recipient, actor,
        coalesce(nullif(trim(issue_reason), ''), item.name || ' item voucher'), 'specific_product',
        item.price_cents, item.price_cents, array[item.id], now(),
        coalesce(expires_at, now() + make_interval(days => item.voucher_valid_days)),
        'active', item.name || ' voucher', item.description
      ) returning id into voucher_id;
      insert into public.notifications(recipient_id, title, body, category, related_entity_type, related_entity_id)
      values (recipient, 'Canteen item voucher issued', item.name || ' has been added to your wallet.', 'voucher', 'voucher_issuance', voucher_id);
      vouchers := vouchers + 1;
    end if;
  end loop;

  insert into public.audit_logs(actor_id, action, entity_type, before_state, after_state, reason, correlation_id)
  values (
    actor, 'canteen.benefits_issued', 'canteen_benefit_batch', null,
    jsonb_build_object('member_ids', member_ids, 'team_ids', team_ids),
    jsonb_build_object('type', benefit_type, 'recipients', recipients, 'amount_cents', amount_cents, 'product_id', product_id),
    issue_reason, request_key
  );
  return query select coalesce(array_length(recipients, 1), 0), credits, vouchers;
end;
$$;

revoke all on function public.complete_canteen_order(uuid, text) from public, anon;
revoke all on function public.save_canteen_category(uuid, text, integer, boolean) from public, anon;
revoke all on function public.complete_canteen_order_by_code(text) from public, anon;
revoke all on function public.issue_canteen_benefits(uuid[], uuid[], text, integer, uuid, timestamptz, text, text) from public, anon;
grant execute on function public.complete_canteen_order(uuid, text) to authenticated;
grant execute on function public.save_canteen_category(uuid, text, integer, boolean) to authenticated;
grant execute on function public.complete_canteen_order_by_code(text) to authenticated;
grant execute on function public.issue_canteen_benefits(uuid[], uuid[], text, integer, uuid, timestamptz, text, text) to authenticated;

create index if not exists canteen_orders_active_operations_idx
  on public.canteen_orders(created_at desc)
  where order_status not in ('draft', 'collected', 'cancelled', 'refunded');
