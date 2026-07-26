alter table public.shop_orders
  add column if not exists stock_released_at timestamptz;

-- Keep the inventory-sensitive implementation private and put the idempotency
-- check in front of it so browser retries cannot reserve stock twice.
alter function public.checkout_shop_cart(text, text)
  rename to checkout_shop_cart_impl;

revoke all on function public.checkout_shop_cart_impl(text, text)
  from public, anon, authenticated;

create function public.checkout_shop_cart(
  request_key text,
  payment_provider text default 'manual'
) returns table(
  order_id uuid,
  order_status text,
  payment_status text,
  total_cents int,
  payment_id uuid
)
language plpgsql
security definer
set search_path = public, app_private, extensions
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  return query
  select o.id, o.status, o.payment_status, o.total_cents, o.payment_id
  from public.shop_orders o
  where o.idempotency_key = request_key
    and o.user_id = auth.uid();

  if found then
    return;
  end if;

  return query
  select *
  from public.checkout_shop_cart_impl(request_key, payment_provider);
end
$$;

revoke all on function public.checkout_shop_cart(text, text)
  from public, anon;
grant execute on function public.checkout_shop_cart(text, text)
  to authenticated;

create or replace function app_private.release_failed_shop_inventory()
returns trigger
language plpgsql
security definer
set search_path = public, app_private
as $$
declare
  target_order public.shop_orders%rowtype;
  item record;
begin
  if new.metadata ->> 'purpose' <> 'shop_order'
     or old.status is not distinct from new.status
     or new.status not in ('failed', 'cancelled') then
    return new;
  end if;

  select *
  into target_order
  from public.shop_orders
  where id = (new.metadata ->> 'shop_order_id')::uuid
  for update;

  if not found or target_order.stock_released_at is not null then
    return new;
  end if;

  for item in
    select *
    from public.shop_order_items
    where order_id = target_order.id
  loop
    if item.product_type = 'canteen' then
      update public.canteen_products
      set stock_quantity = stock_quantity + item.quantity
      where id = item.canteen_product_id
        and stock_quantity is not null;
    else
      update public.merchandise_variants
      set stock_quantity = stock_quantity + item.quantity
      where id = item.merchandise_variant_id;
    end if;
  end loop;

  update public.shop_orders
  set stock_released_at = now(),
      status = 'cancelled',
      payment_status = new.status,
      cancelled_at = coalesce(cancelled_at, now())
  where id = target_order.id;

  perform app_private.write_audit_log(
    'shop.inventory_released',
    'shop_order',
    target_order.id,
    null,
    jsonb_build_object('payment_status', new.status),
    null
  );

  return new;
end
$$;

create trigger payments_release_failed_shop_inventory
after update of status on public.payments
for each row
execute function app_private.release_failed_shop_inventory();
