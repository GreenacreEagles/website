-- Member canteen storefront: persistent cart, wallet/item-voucher checkout,
-- transactional stock protection and pay-at-club order creation.
-- Rollback: drop these RPCs and canteen_cart_items. Remove order columns only
-- after confirming no storefront orders use them.

alter table public.canteen_orders
  add column if not exists payment_method text not null default 'pay_at_club',
  add column if not exists wallet_credit_cents int not null default 0 check (wallet_credit_cents >= 0),
  add column if not exists voucher_discount_cents int not null default 0 check (voucher_discount_cents >= 0),
  add column if not exists amount_due_cents int not null default 0 check (amount_due_cents >= 0);

update public.canteen_orders
set amount_due_cents = case when payment_status = 'paid' then 0 else total_cents end
where amount_due_cents = 0 and total_cents > 0;

alter table public.canteen_orders drop constraint if exists canteen_orders_payment_method_check;
alter table public.canteen_orders add constraint canteen_orders_payment_method_check
  check (payment_method in ('pay_at_club', 'wallet_and_voucher'));

create unique index if not exists canteen_orders_customer_idempotency_idx
  on public.canteen_orders(customer_id, idempotency_key) where idempotency_key is not null;

create table if not exists public.canteen_cart_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  product_id uuid not null references public.canteen_products(id) on delete cascade,
  quantity int not null check (quantity > 0 and quantity <= 50),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, product_id)
);
alter table public.canteen_cart_items enable row level security;

create policy canteen_cart_items_owner_read on public.canteen_cart_items
  for select to authenticated using ((select auth.uid()) = user_id);
create policy canteen_cart_items_owner_insert on public.canteen_cart_items
  for insert to authenticated with check ((select auth.uid()) = user_id);
create policy canteen_cart_items_owner_update on public.canteen_cart_items
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy canteen_cart_items_owner_delete on public.canteen_cart_items
  for delete to authenticated using ((select auth.uid()) = user_id);

-- Sold-out products remain visible; cart and checkout mutations reject them.
drop policy if exists canteen_products_public on public.canteen_products;
create policy canteen_products_public on public.canteen_products
  for select to anon, authenticated using (is_active);

create or replace function public.get_canteen_cart()
returns table (
  cart_item_id uuid, product_id uuid, product_name text, product_description text,
  category_name text, image_url text, image_object_key text, unit_price_cents int,
  quantity int, stock_quantity int, dietary_info text[], allergen_info text[],
  is_available boolean, availability_message text
)
language sql security invoker set search_path = '' as $$
  select ci.id, p.id, p.name, p.description, coalesce(c.name, 'Canteen'),
    p.image_url, p.image_object_key, p.price_cents, ci.quantity, p.stock_quantity,
    p.dietary_info, p.allergen_info,
    (p.is_active and not p.is_sold_out
      and (p.available_from is null or p.available_from <= now())
      and (p.available_until is null or p.available_until > now())
      and (p.stock_quantity is null or p.stock_quantity >= ci.quantity)
      and (p.max_quantity_per_order is null or ci.quantity <= p.max_quantity_per_order)),
    case
      when not p.is_active then 'This item is no longer available'
      when p.is_sold_out then 'This item is sold out'
      when p.available_from is not null and p.available_from > now() then 'This item is not available yet'
      when p.available_until is not null and p.available_until <= now() then 'This item is no longer available'
      when p.stock_quantity is not null and p.stock_quantity < ci.quantity then 'Only ' || p.stock_quantity || ' available'
      when p.max_quantity_per_order is not null and ci.quantity > p.max_quantity_per_order then 'Maximum quantity is ' || p.max_quantity_per_order
      else null end
  from public.canteen_cart_items ci
  join public.canteen_products p on p.id = ci.product_id
  left join public.canteen_categories c on c.id = p.category_id
  where ci.user_id = (select auth.uid()) order by ci.created_at, p.name;
$$;

create or replace function public.set_canteen_cart_item(
  target_product_id uuid, target_quantity int, add_to_existing boolean default false
)
returns int language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid(); product public.canteen_products%rowtype;
  current_quantity int := 0; next_quantity int;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  if target_quantity < -50 then raise exception 'Quantity cannot be less than zero'; end if;
  select * into product from public.canteen_products where id = target_product_id for share;
  if not found or not product.is_active or product.is_sold_out
     or (product.available_from is not null and product.available_from > now())
     or (product.available_until is not null and product.available_until <= now()) then
    raise exception 'That canteen item is not available';
  end if;
  select quantity into current_quantity from public.canteen_cart_items
    where user_id = actor and product_id = target_product_id for update;
  current_quantity := coalesce(current_quantity, 0);
  next_quantity := case when add_to_existing then current_quantity + target_quantity else target_quantity end;
  if next_quantity <= 0 then
    delete from public.canteen_cart_items where user_id = actor and product_id = target_product_id;
    return 0;
  end if;
  if next_quantity > 50 then raise exception 'The maximum quantity for one item is 50'; end if;
  if product.max_quantity_per_order is not null and next_quantity > product.max_quantity_per_order then
    raise exception 'Maximum quantity for this item is %', product.max_quantity_per_order;
  end if;
  if product.stock_quantity is not null and next_quantity > product.stock_quantity then
    raise exception 'Only % available', product.stock_quantity;
  end if;
  insert into public.canteen_cart_items(user_id, product_id, quantity)
  values (actor, target_product_id, next_quantity)
  on conflict (user_id, product_id) do update set quantity = excluded.quantity, updated_at = now();
  return next_quantity;
end;
$$;

create or replace function public.clear_canteen_cart()
returns int language plpgsql security definer set search_path = '' as $$
declare affected int;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  delete from public.canteen_cart_items where user_id = auth.uid();
  get diagnostics affected = row_count; return affected;
end;
$$;

create or replace function public.get_canteen_checkout_wallets()
returns table(wallet_id uuid, wallet_label text, balance_cents int)
language sql security definer set search_path = '' as $$
  select wa.id,
    case when wa.account_type = 'family' then 'Family canteen credit' else 'My canteen credit' end,
    app_private.wallet_balance_cents(wa.id)
  from public.wallet_accounts wa
  where auth.uid() is not null and wa.status = 'active'
    and app_private.can_use_wallet(wa.id) and app_private.wallet_balance_cents(wa.id) > 0
  order by wa.account_type, wa.created_at;
$$;

create or replace function public.get_canteen_checkout_vouchers()
returns table(voucher_id uuid, voucher_name text, allowed_product_ids uuid[], expires_at timestamptz)
language sql security definer set search_path = '' as $$
  select v.id, coalesce(v.name, v.issue_reason, 'Canteen item voucher'),
    v.allowed_product_ids, v.expires_at
  from public.voucher_issuances v
  where auth.uid() is not null and v.beneficiary_id = auth.uid()
    and v.voucher_type = 'specific_product' and v.status = 'active'
    and v.claimed_at is null and v.redemption_count < v.redemption_limit
    and v.valid_from <= now() and (v.expires_at is null or v.expires_at > now())
    and exists (select 1 from public.canteen_cart_items ci
      where ci.user_id = auth.uid() and ci.product_id = any(v.allowed_product_ids))
  order by v.expires_at nulls last, v.created_at;
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
     <> (select count(*) from public.voucher_redemptions where order_id = order_uuid) then
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

grant select, insert, update, delete on public.canteen_cart_items to authenticated;
revoke all on function public.get_canteen_cart() from public, anon;
revoke all on function public.set_canteen_cart_item(uuid, int, boolean) from public, anon;
revoke all on function public.clear_canteen_cart() from public, anon;
revoke all on function public.get_canteen_checkout_wallets() from public, anon;
revoke all on function public.get_canteen_checkout_vouchers() from public, anon;
revoke all on function public.checkout_canteen_cart(text, uuid, int, uuid[], uuid, text) from public, anon;
grant execute on function public.get_canteen_cart() to authenticated;
grant execute on function public.set_canteen_cart_item(uuid, int, boolean) to authenticated;
grant execute on function public.clear_canteen_cart() to authenticated;
grant execute on function public.get_canteen_checkout_wallets() to authenticated;
grant execute on function public.get_canteen_checkout_vouchers() to authenticated;
grant execute on function public.checkout_canteen_cart(text, uuid, int, uuid[], uuid, text) to authenticated;
