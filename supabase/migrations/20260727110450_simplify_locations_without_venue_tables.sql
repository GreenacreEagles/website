-- Replace shared venue records with simple location text and a single fixed club canteen.
-- Existing location names are copied before foreign-key columns and venue tables are removed.

alter table public.teams add column if not exists home_venue text, add column if not exists training_venue text;
alter table public.club_events add column if not exists venue text;
alter table public.fixtures add column if not exists venue text;
alter table public.training_sessions add column if not exists venue text;
alter table public.volunteer_shifts add column if not exists venue text;

update public.teams t set home_venue=coalesce(t.home_venue,nullif(concat_ws(', ',nullif(v.name,''),nullif(v.suburb,'')),'')) from public.venues v where v.id=t.home_venue_id;
update public.teams t set training_venue=coalesce(t.training_venue,nullif(concat_ws(', ',nullif(v.name,''),nullif(v.suburb,'')),'')) from public.venues v where v.id=t.training_venue_id;
update public.club_events e set venue=coalesce(e.venue,nullif(concat_ws(', ',nullif(v.name,''),nullif(v.suburb,'')),'')) from public.venues v where v.id=e.venue_id;
update public.fixtures f set venue=coalesce(f.venue,nullif(concat_ws(', ',nullif(v.name,''),nullif(v.suburb,'')),'')) from public.venues v where v.id=f.venue_id;
update public.training_sessions s set venue=coalesce(s.venue,nullif(concat_ws(', ',nullif(v.name,''),nullif(v.suburb,'')),'')) from public.venues v where v.id=s.venue_id;
update public.volunteer_shifts s set venue=coalesce(s.venue,nullif(concat_ws(', ',nullif(v.name,''),nullif(v.suburb,'')),'')) from public.venues v where v.id=s.venue_id;

alter table public.teams drop constraint if exists teams_home_venue_length, drop constraint if exists teams_training_venue_length;
alter table public.teams add constraint teams_home_venue_length check(home_venue is null or char_length(home_venue)<=240), add constraint teams_training_venue_length check(training_venue is null or char_length(training_venue)<=240);
alter table public.club_events drop constraint if exists club_events_venue_length;
alter table public.club_events add constraint club_events_venue_length check(venue is null or char_length(venue)<=240);
alter table public.fixtures drop constraint if exists fixtures_venue_length;
alter table public.fixtures add constraint fixtures_venue_length check(venue is null or char_length(venue)<=240);
alter table public.training_sessions drop constraint if exists training_sessions_venue_length;
alter table public.training_sessions add constraint training_sessions_venue_length check(venue is null or char_length(venue)<=240);
alter table public.volunteer_shifts drop constraint if exists volunteer_shifts_venue_length;
alter table public.volunteer_shifts add constraint volunteer_shifts_venue_length check(venue is null or char_length(venue)<=240);

alter table public.teams drop column if exists home_venue_id, drop column if exists training_venue_id;
alter table public.club_events drop column if exists venue_id;
alter table public.fixtures drop column if exists venue_id;
alter table public.training_sessions drop column if exists venue_id;
alter table public.volunteer_shifts drop column if exists venue_id;
alter table public.canteen_orders drop column if exists venue_id;
alter table public.voucher_issuances drop column if exists venue_id;
alter table public.voucher_redemptions drop column if exists venue_id;

drop table if exists public.canteen_venues;
drop table if exists public.venues;

create or replace function app_private.redeem_voucher(
  redemption_token text,
  redeem_venue_id uuid,
  redeem_amount_cents int,
  redeem_order_id uuid default null,
  device_label text default null
)
returns table (
  redemption_id uuid,
  voucher_id uuid,
  remaining_value_cents int,
  result text
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v public.voucher_issuances%rowtype;
  new_redemption_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not app_private.has_permission('canteen.vouchers.redeem', null, null) then
    raise exception 'Worker not authorised';
  end if;

  if redeem_amount_cents <= 0 then
    raise exception 'Invalid redemption amount';
  end if;

  select *
  into v
  from public.voucher_issuances
  where token_hash = encode(extensions.digest(redemption_token, 'sha256'), 'hex')
  for update;

  if not found then
    raise exception 'Invalid token';
  end if;

  if v.status <> 'active' then
    raise exception 'Voucher not active';
  end if;

  if v.valid_from > now() then
    raise exception 'Voucher not active';
  end if;

  if v.expires_at is not null and v.expires_at <= now() then
    raise exception 'Expired voucher';
  end if;


  if v.redemption_count >= v.redemption_limit then
    raise exception 'Already redeemed';
  end if;

  if v.remaining_value_cents < redeem_amount_cents then
    raise exception 'Insufficient balance';
  end if;

  update public.voucher_issuances
  set remaining_value_cents = remaining_value_cents - redeem_amount_cents,
      redemption_count = redemption_count + 1,
      claimed_at = coalesce(claimed_at, now()),
      status = case
        when redemption_count + 1 >= redemption_limit or remaining_value_cents - redeem_amount_cents = 0 then 'claimed'
        else status
      end,
      updated_at = now()
  where id = v.id;

  insert into public.voucher_redemptions (voucher_id, redeemed_by, order_id, amount_cents, device_label)
  values (v.id, auth.uid(), redeem_order_id, redeem_amount_cents, device_label)
  returning id into new_redemption_id;

  perform app_private.write_audit_log('voucher.redeemed', 'voucher_issuance', v.id, to_jsonb(v), null, null);

  return query
  select new_redemption_id, v.id, v.remaining_value_cents - redeem_amount_cents, 'redeemed'::text;
end;
$$;


create or replace function app_private.create_canteen_order(
  target_product_id uuid,
  target_venue_id uuid default null,
  target_beneficiary_id uuid default null,
  order_quantity int default 1,
  target_pickup_window_start timestamptz default null,
  target_special_instructions text default null
)
returns table (
  order_id uuid,
  order_number text,
  payment_status text,
  order_status text,
  total_cents int
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  product public.canteen_products%rowtype;
  new_order_id uuid;
  new_order_number text;
  raw_pickup_code text;
  recipient uuid;
  subtotal int;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if order_quantity < 1 or order_quantity > 20 then
    raise exception 'Invalid quantity';
  end if;

  select *
  into product
  from public.canteen_products
  where id = target_product_id
  for update;

  if not found or not product.is_active or product.is_sold_out then
    raise exception 'That canteen item is not available';
  end if;

  if product.max_quantity_per_order is not null and order_quantity > product.max_quantity_per_order then
    raise exception 'Maximum quantity for this item is %', product.max_quantity_per_order;
  end if;

  if product.stock_quantity is not null and product.stock_quantity < order_quantity then
    raise exception 'Not enough stock available';
  end if;

  recipient := coalesce(target_beneficiary_id, auth.uid());

  if recipient <> auth.uid() and not exists (
    select 1
    from public.family_members child
    join public.family_members guardian on guardian.family_id = child.family_id
    where child.user_id = recipient
      and child.status = 'active'
      and child.relationship in ('child', 'player', 'dependent')
      and guardian.user_id = auth.uid()
      and guardian.status = 'active'
      and guardian.relationship in ('parent', 'guardian', 'carer')
  ) then
    raise exception 'You can only order for linked family members';
  end if;

  subtotal := product.price_cents * order_quantity;
  new_order_number := 'GE-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
  raw_pickup_code := 'GEORDER:' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));

  insert into public.canteen_orders (
    order_number,
    customer_id,
    recipient_id,
    pickup_window_start,
    subtotal_cents,
    total_cents,
    payment_status,
    order_status,
    pickup_code,
    pickup_token_hash,
    special_instructions
  )
  values (
    new_order_number,
    auth.uid(),
    recipient,
    target_pickup_window_start,
    subtotal,
    subtotal,
    case when subtotal = 0 then 'paid' else 'unpaid' end,
    'accepted',
    raw_pickup_code,
    encode(extensions.digest(raw_pickup_code, 'sha256'), 'hex'),
    nullif(left(coalesce(target_special_instructions, ''), 500), '')
  )
  returning id into new_order_id;

  insert into public.canteen_order_items (
    order_id,
    product_id,
    product_name_snapshot,
    unit_price_cents_snapshot,
    quantity,
    allergen_snapshot,
    line_total_cents,
    fulfilment_type_snapshot
  )
  values (
    new_order_id,
    product.id,
    product.name,
    product.price_cents,
    order_quantity,
    product.allergen_info,
    subtotal,
    product.fulfilment_type
  );

  if product.stock_quantity is not null then
    update public.canteen_products
    set stock_quantity = stock_quantity - order_quantity,
        is_sold_out = stock_quantity - order_quantity <= 0,
        updated_at = now()
    where id = product.id;

    insert into public.inventory_movements (
      product_id,
      movement_type,
      quantity,
      reason,
      related_entity_type,
      related_entity_id,
      created_by
    )
    values (
      product.id,
      'reserve',
      -order_quantity,
      'Reserved for order ' || new_order_number,
      'canteen_order',
      new_order_id,
      auth.uid()
    );
  end if;

  perform app_private.write_audit_log(
    'canteen.order_created',
    'canteen_order',
    new_order_id,
    null,
    jsonb_build_object('product_id', product.id, 'quantity', order_quantity, 'recipient_id', recipient),
    null
  );

  return query
  select new_order_id, new_order_number, case when subtotal = 0 then 'paid' else 'unpaid' end, 'accepted'::text, subtotal;
end;
$$;


create or replace function public.checkout_canteen_cart(
  request_key text,
  target_wallet_id uuid default null,
  target_wallet_cents int default 0,
  target_voucher_ids uuid[] default '{}'::uuid[],
  target_venue_id uuid default null,
  target_notes text default null
)
returns table (
  order_id uuid, order_number text, payment_status text, order_status text,
  subtotal_cents int, voucher_discount_cents int, wallet_credit_cents int,
  amount_due_cents int, pickup_code text
)
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid(); existing public.canteen_orders%rowtype;
  order_uuid uuid := gen_random_uuid();
  order_no text := 'GE-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
  raw_pickup text := 'GEORDER:' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 16));
  line record; voucher public.voucher_issuances%rowtype;
  chosen_product uuid; chosen_price int; already_used int;
  voucher_uses jsonb := '{}'::jsonb;
  subtotal int := 0; voucher_total int := 0; wallet_total int := 0;
  due int; wallet_balance int; final_payment text; final_status text;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  if nullif(trim(request_key), '') is null or length(request_key) > 120 then raise exception 'Missing request key'; end if;
  if target_wallet_cents < 0 then raise exception 'Invalid wallet amount'; end if;
  if coalesce(array_length(target_voucher_ids, 1), 0) > 50 then raise exception 'Too many vouchers selected'; end if;

  select * into existing from public.canteen_orders
  where customer_id = actor and idempotency_key = request_key;
  if found then
    return query select existing.id, existing.order_number, existing.payment_status, existing.order_status,
      existing.subtotal_cents, existing.voucher_discount_cents, existing.wallet_credit_cents,
      existing.amount_due_cents, existing.pickup_code;
    return;
  end if;
  if not exists (select 1 from public.canteen_cart_items where user_id = actor) then
    raise exception 'Your cart is empty';
  end if;

  -- Lock products in stable order before validating and calculating server totals.
  for line in
    select ci.product_id as cart_product_id, ci.quantity as cart_quantity, p.*
    from public.canteen_cart_items ci join public.canteen_products p on p.id = ci.product_id
    where ci.user_id = actor order by ci.product_id for update of p
  loop
    if not line.is_active or line.is_sold_out
       or (line.available_from is not null and line.available_from > now())
       or (line.available_until is not null and line.available_until <= now()) then
      raise exception 'An item in your cart is no longer available';
    end if;
    if line.max_quantity_per_order is not null and line.cart_quantity > line.max_quantity_per_order then
      raise exception 'Maximum quantity for % is %', line.name, line.max_quantity_per_order;
    end if;
    if line.stock_quantity is not null and line.stock_quantity < line.cart_quantity then
      raise exception 'Only % of % available', line.stock_quantity, line.name;
    end if;
    subtotal := subtotal + (line.price_cents * line.cart_quantity);
  end loop;

  insert into public.canteen_orders(
    id, order_number, customer_id, recipient_id, subtotal_cents,
    discount_cents, total_cents, payment_status, order_status, payment_method,
    wallet_credit_cents, voucher_discount_cents, amount_due_cents, pickup_code,
    pickup_token_hash, qr_token_hash, special_instructions, idempotency_key
  ) values (
    order_uuid, order_no, actor, actor, subtotal,
    0, subtotal, 'awaiting_payment', 'awaiting_payment', 'pay_at_club',
    0, 0, subtotal, raw_pickup,
    encode(extensions.digest(raw_pickup, 'sha256'), 'hex'),
    encode(extensions.digest(raw_pickup, 'sha256'), 'hex'),
    nullif(left(trim(coalesce(target_notes, '')), 500), ''), request_key
  );

  insert into public.canteen_order_items(
    order_id, product_id, product_name_snapshot, unit_price_cents_snapshot,
    quantity, options_snapshot, allergen_snapshot, line_total_cents, fulfilment_type_snapshot
  )
  select order_uuid, p.id, p.name, p.price_cents, ci.quantity,
    jsonb_build_object('dietary_info', p.dietary_info), p.allergen_info,
    p.price_cents * ci.quantity, p.fulfilment_type
  from public.canteen_cart_items ci join public.canteen_products p on p.id = ci.product_id
  where ci.user_id = actor;

  for voucher in
    select * from public.voucher_issuances
    where id = any(coalesce(target_voucher_ids, '{}'::uuid[])) order by id for update
  loop
    if voucher.beneficiary_id <> actor or voucher.voucher_type <> 'specific_product'
       or voucher.status <> 'active' or voucher.claimed_at is not null
       or voucher.redemption_count >= voucher.redemption_limit
       or voucher.valid_from > now()
       or (voucher.expires_at is not null and voucher.expires_at <= now()) then
      raise exception 'A selected voucher is no longer available';
    end if;
    chosen_product := null;
    select ci.product_id, p.price_cents into chosen_product, chosen_price
    from public.canteen_cart_items ci join public.canteen_products p on p.id = ci.product_id
    where ci.user_id = actor and ci.product_id = any(voucher.allowed_product_ids)
      and coalesce((voucher_uses->>ci.product_id::text)::int, 0) < ci.quantity
    order by ci.created_at limit 1;
    if chosen_product is null then raise exception 'A selected voucher does not match an available cart item'; end if;
    already_used := coalesce((voucher_uses->>chosen_product::text)::int, 0);
    voucher_uses := jsonb_set(voucher_uses, array[chosen_product::text], to_jsonb(already_used + 1), true);
    voucher_total := voucher_total + chosen_price;
    insert into public.voucher_redemptions(voucher_id, redeemed_by, order_id, amount_cents, status, device_label)
      values (voucher.id, actor, order_uuid, chosen_price, 'completed', 'Member canteen checkout');
    update public.voucher_issuances set remaining_value_cents = 0,
      redemption_count = redemption_count + 1, status = 'claimed', claimed_at = now(), updated_at = now()
      where id = voucher.id;
  end loop;

  -- Reject forged or unavailable voucher IDs rather than silently ignoring them.
  if (select count(distinct value) from unnest(coalesce(target_voucher_ids, '{}'::uuid[])) value)
     <> (select count(*) from public.voucher_redemptions vr where vr.order_id = order_uuid) then
    raise exception 'A selected voucher is no longer available';
  end if;

  due := greatest(subtotal - voucher_total, 0);
  if target_wallet_cents > 0 then
    if target_wallet_id is null then raise exception 'Choose a wallet for canteen credit'; end if;
    perform 1 from public.wallet_accounts wa where wa.id = target_wallet_id for update;
    if not found or not app_private.can_use_wallet(target_wallet_id) then raise exception 'Wallet not available'; end if;
    wallet_balance := app_private.wallet_balance_cents(target_wallet_id);
    if target_wallet_cents > wallet_balance then raise exception 'Insufficient wallet balance'; end if;
    wallet_total := least(target_wallet_cents, due);
    if wallet_total > 0 then
      perform app_private.apply_wallet_entry(target_wallet_id, wallet_total, 'debit',
        'canteen_order', 'canteen-order:' || order_uuid, 'Canteen order ' || order_no, actor);
      update public.wallet_ledger_entries
      set related_entity_type = 'canteen_order', related_entity_id = order_uuid
      where wallet_account_id = target_wallet_id and idempotency_key = 'canteen-order:' || order_uuid;
    end if;
  end if;

  due := greatest(subtotal - voucher_total - wallet_total, 0);
  final_payment := case when due = 0 then 'paid' else 'awaiting_payment' end;
  final_status := case when due = 0 then 'accepted' else 'awaiting_payment' end;
  update public.canteen_orders set discount_cents = voucher_total + wallet_total,
    total_cents = due, payment_status = final_payment, order_status = final_status,
    payment_method = case when due > 0 then 'pay_at_club' else 'wallet_and_voucher' end,
    wallet_credit_cents = wallet_total, voucher_discount_cents = voucher_total,
    amount_due_cents = due, updated_at = now() where id = order_uuid;

  update public.canteen_products p set stock_quantity = p.stock_quantity - ci.quantity,
    is_sold_out = p.stock_quantity - ci.quantity <= 0, updated_at = now()
  from public.canteen_cart_items ci
  where ci.user_id = actor and ci.product_id = p.id and p.stock_quantity is not null;
  insert into public.inventory_movements(product_id, movement_type, quantity, reason,
    related_entity_type, related_entity_id, created_by)
  select ci.product_id, 'reserve', -ci.quantity, 'Reserved for order ' || order_no,
    'canteen_order', order_uuid, actor
  from public.canteen_cart_items ci join public.canteen_products p on p.id = ci.product_id
  where ci.user_id = actor and p.stock_quantity is not null;

  insert into public.order_status_history(order_id, old_status, new_status, changed_by, reason)
    values (order_uuid, null, final_status, actor, 'Placed through the member canteen store');
  perform app_private.write_audit_log('canteen.order_created', 'canteen_order', order_uuid, null,
    jsonb_build_object('subtotal_cents', subtotal, 'voucher_discount_cents', voucher_total,
      'wallet_credit_cents', wallet_total, 'amount_due_cents', due,
      'payment_status', final_payment, 'order_status', final_status), null);
  delete from public.canteen_cart_items where user_id = actor;
  return query select order_uuid, order_no, final_payment, final_status,
    subtotal, voucher_total, wallet_total, due, raw_pickup;
end;
$$;


-- Legacy UUID parameters remain temporarily in these RPC signatures for migration compatibility,
-- but are ignored. The application no longer sends or displays a venue selection.
