-- Qualify the voucher redemption column inside checkout; the function also returns an order_id column.

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
    id, order_number, venue_id, customer_id, recipient_id, subtotal_cents,
    discount_cents, total_cents, payment_status, order_status, payment_method,
    wallet_credit_cents, voucher_discount_cents, amount_due_cents, pickup_code,
    pickup_token_hash, qr_token_hash, special_instructions, idempotency_key
  ) values (
    order_uuid, order_no, target_venue_id, actor, actor, subtotal,
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
    insert into public.voucher_redemptions(voucher_id, redeemed_by, venue_id, order_id, amount_cents, status, device_label)
      values (voucher.id, actor, target_venue_id, order_uuid, chosen_price, 'completed', 'Member canteen checkout');
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
    payment_method = case when wallet_total + voucher_total > 0 then 'wallet_and_voucher' else 'pay_at_club' end,
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

