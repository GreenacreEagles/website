-- Member-facing merchandise cart and pay-at-club checkout.
--
-- Reuses the existing shop_cart_items table for durable cart storage while
-- keeping the disabled combined canteen/merchandise checkout closed. Orders
-- continue to use merchandise_orders so the existing admin workflow remains
-- authoritative.

alter table public.merchandise_orders
  add column if not exists payment_method text,
  add column if not exists payment_status text,
  add column if not exists idempotency_key text;

update public.merchandise_orders
set payment_method = coalesce(payment_method, 'pay_at_club'),
    payment_status = coalesce(
      payment_status,
      case
        when status = 'awaiting_payment' then 'awaiting_payment'
        when status in ('paid', 'processing', 'awaiting_stock', 'ready_for_pickup', 'shipped', 'collected', 'completed') then 'paid'
        when status = 'cancelled' then 'cancelled'
        when status = 'refunded' then 'refunded'
        when status = 'partially_refunded' then 'partially_refunded'
        else 'awaiting_payment'
      end
    )
where payment_method is null
   or payment_status is null;

alter table public.merchandise_orders
  alter column payment_method set default 'pay_at_club',
  alter column payment_method set not null,
  alter column payment_status set default 'awaiting_payment',
  alter column payment_status set not null;

alter table public.merchandise_orders
  drop constraint if exists merchandise_orders_payment_method_check;
alter table public.merchandise_orders
  add constraint merchandise_orders_payment_method_check
  check (payment_method in ('pay_at_club', 'online'));

alter table public.merchandise_orders
  drop constraint if exists merchandise_orders_payment_status_check;
alter table public.merchandise_orders
  add constraint merchandise_orders_payment_status_check
  check (payment_status in ('awaiting_payment', 'paid', 'cancelled', 'refunded', 'partially_refunded'));

create unique index if not exists merchandise_orders_customer_idempotency_idx
  on public.merchandise_orders(customer_id, idempotency_key)
  where idempotency_key is not null;

drop policy if exists merchandise_order_history_manager_read
  on public.merchandise_order_status_history;
drop policy if exists merchandise_order_history_own_or_manager_read
  on public.merchandise_order_status_history;
create policy merchandise_order_history_own_or_manager_read
on public.merchandise_order_status_history
for select
to authenticated
using (
  app_private.has_permission('merchandise.manage')
  or exists (
    select 1
    from public.merchandise_orders mo
    where mo.id = order_id
      and mo.customer_id = (select auth.uid())
  )
);

create or replace function public.get_merchandise_cart()
returns table (
  cart_item_id uuid,
  variant_id uuid,
  product_id uuid,
  product_name text,
  product_description text,
  category text,
  image_url text,
  image_object_key text,
  variant_label text,
  sku text,
  unit_price_cents int,
  quantity int,
  stock_quantity int,
  is_available boolean,
  availability_message text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app_private, extensions
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  return query
  select
    c.id,
    v.id,
    p.id,
    p.name,
    p.description,
    coalesce(p.category, 'Club merchandise'),
    p.image_url,
    p.image_object_key,
    nullif(concat_ws(' / ', v.size, v.colour), ''),
    v.sku,
    coalesce(v.sale_price_cents, v.price_cents),
    c.quantity,
    v.stock_quantity,
    (
      p.status = 'active'
      and v.is_active
      and (p.available_from is null or p.available_from <= now())
      and (p.available_until is null or p.available_until > now())
      and v.stock_quantity >= c.quantity
    ),
    case
      when p.status <> 'active' or not v.is_active then 'This item is no longer available.'
      when p.available_from is not null and p.available_from > now() then 'This item is not available yet.'
      when p.available_until is not null and p.available_until <= now() then 'This item is no longer available.'
      when v.stock_quantity = 0 then 'This item is sold out.'
      when v.stock_quantity < c.quantity then 'Only ' || v.stock_quantity || ' remain in stock.'
      else null
    end
  from public.shop_cart_items c
  join public.merchandise_variants v on v.id = c.merchandise_variant_id
  join public.merchandise_products p on p.id = v.product_id
  where c.user_id = auth.uid()
    and c.product_type = 'merchandise'
  order by c.created_at, c.id;
end
$$;

create or replace function public.set_merchandise_cart_item(
  target_variant_id uuid,
  target_quantity int,
  add_to_existing boolean default false
)
returns table (
  item_count int,
  total_quantity int
)
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, extensions
as $$
declare
  existing_quantity int;
  next_quantity int;
  variant_row record;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if (not add_to_existing and (target_quantity < 0 or target_quantity > 50))
     or (add_to_existing and (target_quantity < -50 or target_quantity > 50)) then
    raise exception 'Quantity change is outside the allowed range';
  end if;

  select c.quantity
  into existing_quantity
  from public.shop_cart_items c
  where c.user_id = auth.uid()
    and c.product_type = 'merchandise'
    and c.merchandise_variant_id = target_variant_id
  for update;

  next_quantity := case
    when add_to_existing then coalesce(existing_quantity, 0) + target_quantity
    else target_quantity
  end;

  if next_quantity < 0 then
    raise exception 'Quantity cannot be less than zero';
  end if;

  if next_quantity > 50 then
    raise exception 'The maximum quantity for one item is 50';
  end if;

  if next_quantity = 0 then
    delete from public.shop_cart_items
    where user_id = auth.uid()
      and product_type = 'merchandise'
      and merchandise_variant_id = target_variant_id;
  else
    select
      v.stock_quantity,
      v.is_active,
      p.status as product_status,
      p.available_from,
      p.available_until,
      p.name as product_name
    into variant_row
    from public.merchandise_variants v
    join public.merchandise_products p on p.id = v.product_id
    where v.id = target_variant_id;

    if not found
       or not variant_row.is_active
       or variant_row.product_status <> 'active'
       or (variant_row.available_from is not null and variant_row.available_from > now())
       or (variant_row.available_until is not null and variant_row.available_until <= now()) then
      raise exception 'That merchandise item is not available';
    end if;

    if variant_row.stock_quantity < next_quantity then
      raise exception 'Only % of % remain in stock', variant_row.stock_quantity, variant_row.product_name;
    end if;

    insert into public.shop_cart_items (
      user_id,
      product_type,
      merchandise_variant_id,
      quantity
    )
    values (
      auth.uid(),
      'merchandise',
      target_variant_id,
      next_quantity
    )
    on conflict (user_id, merchandise_variant_id)
      where merchandise_variant_id is not null
    do update
    set quantity = excluded.quantity,
        updated_at = now();
  end if;

  return query
  select
    count(*)::int,
    coalesce(sum(c.quantity), 0)::int
  from public.shop_cart_items c
  where c.user_id = auth.uid()
    and c.product_type = 'merchandise';
end
$$;

create or replace function public.clear_merchandise_cart()
returns int
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  removed_count int;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  delete from public.shop_cart_items
  where user_id = auth.uid()
    and product_type = 'merchandise';

  get diagnostics removed_count = row_count;
  return removed_count;
end
$$;

create or replace function public.checkout_merchandise_cart(
  request_key text,
  target_notes text default null
)
returns table (
  order_id uuid,
  order_number text,
  order_status text,
  payment_status text,
  payment_method text,
  total_cents int
)
language plpgsql
security definer
set search_path = pg_catalog, public, app_private, extensions
as $$
declare
  existing_order public.merchandise_orders%rowtype;
  cart_row record;
  variant_row record;
  new_order_id uuid;
  new_order_number text;
  unit_price int;
  running_total bigint := 0;
  line_count int := 0;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if request_key is null
     or length(request_key) < 16
     or length(request_key) > 120
     or request_key !~ '^[A-Za-z0-9_-]+$' then
    raise exception 'Invalid checkout request';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(auth.uid()::text || ':' || request_key, 0)
  );

  select *
  into existing_order
  from public.merchandise_orders mo
  where mo.customer_id = auth.uid()
    and mo.idempotency_key = request_key;

  if found then
    return query
    select
      existing_order.id,
      existing_order.order_number,
      existing_order.status,
      existing_order.payment_status,
      existing_order.payment_method,
      existing_order.total_cents;
    return;
  end if;

  if not exists (
    select 1
    from public.shop_cart_items c
    where c.user_id = auth.uid()
      and c.product_type = 'merchandise'
  ) then
    raise exception 'Your cart is empty';
  end if;

  new_order_id := gen_random_uuid();
  new_order_number := 'GM-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));

  insert into public.merchandise_orders (
    id,
    order_number,
    customer_id,
    total_cents,
    status,
    pickup_or_delivery,
    notes,
    payment_method,
    payment_status,
    idempotency_key
  )
  values (
    new_order_id,
    new_order_number,
    auth.uid(),
    0,
    'awaiting_payment',
    'pickup',
    nullif(left(coalesce(target_notes, ''), 500), ''),
    'pay_at_club',
    'awaiting_payment',
    request_key
  );

  for cart_row in
    select c.id, c.merchandise_variant_id, c.quantity
    from public.shop_cart_items c
    where c.user_id = auth.uid()
      and c.product_type = 'merchandise'
    order by c.merchandise_variant_id
    for update
  loop
    select
      v.id,
      v.product_id,
      v.sku,
      v.size,
      v.colour,
      v.price_cents,
      v.sale_price_cents,
      v.stock_quantity,
      v.is_active,
      p.name as product_name,
      p.status as product_status,
      p.available_from,
      p.available_until
    into variant_row
    from public.merchandise_variants v
    join public.merchandise_products p on p.id = v.product_id
    where v.id = cart_row.merchandise_variant_id
    for update of v, p;

    if not found
       or not variant_row.is_active
       or variant_row.product_status <> 'active'
       or (variant_row.available_from is not null and variant_row.available_from > now())
       or (variant_row.available_until is not null and variant_row.available_until <= now()) then
      raise exception 'An item in your cart is no longer available';
    end if;

    if variant_row.stock_quantity < cart_row.quantity then
      raise exception 'Only % of % remain in stock', variant_row.stock_quantity, variant_row.product_name;
    end if;

    unit_price := coalesce(variant_row.sale_price_cents, variant_row.price_cents);
    running_total := running_total + (unit_price::bigint * cart_row.quantity);
    line_count := line_count + 1;

    if running_total > 2147483647 then
      raise exception 'Order total is too large';
    end if;

    insert into public.merchandise_order_items (
      order_id,
      product_id,
      variant_id,
      product_name_snapshot,
      variant_label_snapshot,
      sku_snapshot,
      unit_price_cents_snapshot,
      quantity,
      line_total_cents
    )
    values (
      new_order_id,
      variant_row.product_id,
      variant_row.id,
      variant_row.product_name,
      nullif(concat_ws(' / ', variant_row.size, variant_row.colour), ''),
      variant_row.sku,
      unit_price,
      cart_row.quantity,
      unit_price * cart_row.quantity
    );

    update public.merchandise_variants
    set stock_quantity = stock_quantity - cart_row.quantity,
        updated_at = now()
    where id = variant_row.id;
  end loop;

  update public.merchandise_orders
  set total_cents = running_total::int,
      updated_at = now()
  where id = new_order_id;

  insert into public.merchandise_order_status_history (
    order_id,
    old_status,
    new_status,
    changed_by,
    reason
  )
  values (
    new_order_id,
    null,
    'awaiting_payment',
    auth.uid(),
    'Pay at club order placed'
  );

  delete from public.shop_cart_items
  where user_id = auth.uid()
    and product_type = 'merchandise';

  perform app_private.write_audit_log(
    'merchandise.order_created',
    'merchandise_order',
    new_order_id,
    null,
    jsonb_build_object(
      'item_count', line_count,
      'total_cents', running_total,
      'payment_method', 'pay_at_club'
    ),
    null
  );

  return query
  select
    new_order_id,
    new_order_number,
    'awaiting_payment'::text,
    'awaiting_payment'::text,
    'pay_at_club'::text,
    running_total::int;
end
$$;

create or replace function app_private.sync_merchandise_payment_state()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if new.status = 'paid' and old.status is distinct from new.status then
    new.payment_status := 'paid';
    new.paid_at := coalesce(new.paid_at, now());
  elsif new.status = 'cancelled'
        and old.status is distinct from new.status
        and old.payment_status = 'awaiting_payment' then
    new.payment_status := 'cancelled';
  elsif new.status = 'refunded' and old.status is distinct from new.status then
    new.payment_status := 'refunded';
  elsif new.status = 'partially_refunded' and old.status is distinct from new.status then
    new.payment_status := 'partially_refunded';
  end if;

  return new;
end
$$;

drop trigger if exists merchandise_orders_sync_payment_state
  on public.merchandise_orders;
create trigger merchandise_orders_sync_payment_state
before update of status
on public.merchandise_orders
for each row
execute function app_private.sync_merchandise_payment_state();

-- The member checkout is RPC-only. Prevent browser callers from inserting
-- authoritative totals, ownership or payment state directly.
revoke insert, update, delete
  on public.merchandise_orders
  from anon, authenticated;
revoke insert, update, delete
  on public.merchandise_order_items
  from anon, authenticated;
revoke insert, update, delete
  on public.merchandise_order_status_history
  from anon, authenticated;
revoke select
  on public.merchandise_orders,
     public.merchandise_order_items,
     public.merchandise_order_status_history,
     public.shop_cart_items
  from anon;
revoke select, insert, update, delete
  on public.shop_cart_items
  from authenticated;

grant select
  on public.merchandise_orders,
     public.merchandise_order_items,
     public.merchandise_order_status_history
  to authenticated;

revoke all on function public.get_merchandise_cart()
  from public, anon;
revoke all on function public.set_merchandise_cart_item(uuid, int, boolean)
  from public, anon;
revoke all on function public.clear_merchandise_cart()
  from public, anon;
revoke all on function public.checkout_merchandise_cart(text, text)
  from public, anon;

grant execute on function public.get_merchandise_cart()
  to authenticated;
grant execute on function public.set_merchandise_cart_item(uuid, int, boolean)
  to authenticated;
grant execute on function public.clear_merchandise_cart()
  to authenticated;
grant execute on function public.checkout_merchandise_cart(text, text)
  to authenticated;

-- Retire the previous single-line, non-idempotent member checkout.
revoke execute on function public.create_merchandise_order(uuid, int, text, text)
  from authenticated;
