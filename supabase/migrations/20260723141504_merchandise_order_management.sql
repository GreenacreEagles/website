-- Merchandise order line items, stock-safe checkout and protected order operations.

create table if not exists public.merchandise_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.merchandise_orders(id) on delete cascade,
  product_id uuid references public.merchandise_products(id) on delete set null,
  variant_id uuid references public.merchandise_variants(id) on delete set null,
  product_name_snapshot text not null,
  variant_label_snapshot text,
  sku_snapshot text,
  unit_price_cents_snapshot int not null check (unit_price_cents_snapshot >= 0),
  quantity int not null check (quantity > 0),
  line_total_cents int not null check (line_total_cents >= 0),
  created_at timestamptz not null default now()
);

alter table public.merchandise_orders
add column if not exists paid_at timestamptz,
add column if not exists stock_released_at timestamptz;

create table if not exists public.merchandise_order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.merchandise_orders(id) on delete cascade,
  old_status text,
  new_status text not null,
  changed_by uuid references public.profiles(id) on delete set null,
  reason text,
  created_at timestamptz not null default now()
);

create index if not exists merchandise_order_items_order_idx
on public.merchandise_order_items (order_id);

create index if not exists merchandise_order_items_variant_idx
on public.merchandise_order_items (variant_id);

create index if not exists merchandise_orders_status_created_idx
on public.merchandise_orders (status, created_at);

alter table public.merchandise_order_items enable row level security;
alter table public.merchandise_order_status_history enable row level security;

drop policy if exists merchandise_order_items_read_own_or_manager on public.merchandise_order_items;
create policy merchandise_order_items_read_own_or_manager
on public.merchandise_order_items
for select
to authenticated
using (
  app_private.has_permission('merchandise.manage')
  or exists (
    select 1
    from public.merchandise_orders mo
    where mo.id = order_id
      and mo.customer_id = auth.uid()
  )
);

drop policy if exists merchandise_order_history_manager_read on public.merchandise_order_status_history;
create policy merchandise_order_history_manager_read
on public.merchandise_order_status_history
for select
to authenticated
using (app_private.has_permission('merchandise.manage'));

create or replace function app_private.create_merchandise_order(
  target_variant_id uuid,
  order_quantity int default 1,
  target_pickup_or_delivery text default 'pickup',
  target_notes text default null
)
returns table (
  order_id uuid,
  order_number text,
  order_status text,
  total_cents int
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  variant record;
  new_order_id uuid;
  new_order_number text;
  unit_price int;
  line_total int;
  variant_label text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if order_quantity < 1 or order_quantity > 10 then
    raise exception 'Invalid quantity';
  end if;

  if target_pickup_or_delivery not in ('pickup', 'delivery') then
    raise exception 'Invalid fulfilment option';
  end if;

  select
    mv.*,
    mp.name as product_name,
    mp.status as product_status
  into variant
  from public.merchandise_variants mv
  join public.merchandise_products mp on mp.id = mv.product_id
  where mv.id = target_variant_id
  for update of mv;

  if not found or not variant.is_active or variant.product_status <> 'active' then
    raise exception 'That merchandise item is not available';
  end if;

  if variant.stock_quantity < order_quantity then
    raise exception 'Not enough stock available';
  end if;

  unit_price := coalesce(variant.sale_price_cents, variant.price_cents);
  line_total := unit_price * order_quantity;
  new_order_number := 'GM-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
  variant_label := nullif(array_to_string(array_remove(array[variant.size, variant.colour], null), ' / '), '');

  insert into public.merchandise_orders (
    order_number,
    customer_id,
    total_cents,
    status,
    pickup_or_delivery,
    notes
  )
  values (
    new_order_number,
    auth.uid(),
    line_total,
    'awaiting_payment',
    target_pickup_or_delivery,
    nullif(left(coalesce(target_notes, ''), 500), '')
  )
  returning id into new_order_id;

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
    variant.product_id,
    variant.id,
    variant.product_name,
    variant_label,
    variant.sku,
    unit_price,
    order_quantity,
    line_total
  );

  update public.merchandise_variants
  set stock_quantity = stock_quantity - order_quantity,
      updated_at = now()
  where id = variant.id;

  perform app_private.write_audit_log(
    'merchandise.order_created',
    'merchandise_order',
    new_order_id,
    null,
    jsonb_build_object('variant_id', variant.id, 'quantity', order_quantity),
    null
  );

  return query select new_order_id, new_order_number, 'awaiting_payment'::text, line_total;
end;
$$;

create or replace function app_private.update_merchandise_order_state(
  target_order_id uuid,
  target_status text,
  change_reason text default null
)
returns table (
  order_id uuid,
  order_number text,
  old_status text,
  new_status text,
  customer_id uuid
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  order_row public.merchandise_orders%rowtype;
  item record;
  should_release_stock boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not app_private.has_permission('merchandise.manage') then
    raise exception 'Worker not authorised';
  end if;

  select *
  into order_row
  from public.merchandise_orders
  where id = target_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if target_status not in ('awaiting_payment','paid','processing','awaiting_stock','ready_for_pickup','shipped','collected','completed','cancelled','refunded','partially_refunded') then
    raise exception 'Invalid order status';
  end if;

  if order_row.status in ('completed','cancelled','refunded') and target_status <> order_row.status then
    raise exception 'Closed orders cannot be moved';
  end if;

  if order_row.status = 'awaiting_payment' and target_status not in ('awaiting_payment','paid','cancelled') then
    raise exception 'Invalid status transition';
  end if;

  if order_row.status = 'paid' and target_status not in ('paid','processing','awaiting_stock','ready_for_pickup','shipped','cancelled','refunded','partially_refunded') then
    raise exception 'Invalid status transition';
  end if;

  if order_row.status = 'processing' and target_status not in ('processing','awaiting_stock','ready_for_pickup','shipped','cancelled','refunded','partially_refunded') then
    raise exception 'Invalid status transition';
  end if;

  if order_row.status = 'awaiting_stock' and target_status not in ('awaiting_stock','processing','ready_for_pickup','cancelled','refunded') then
    raise exception 'Invalid status transition';
  end if;

  if order_row.status = 'ready_for_pickup' and target_status not in ('ready_for_pickup','collected','cancelled','refunded') then
    raise exception 'Invalid status transition';
  end if;

  if order_row.status = 'shipped' and target_status not in ('shipped','completed','refunded','partially_refunded') then
    raise exception 'Invalid status transition';
  end if;

  if order_row.status = 'collected' and target_status not in ('collected','completed','refunded','partially_refunded') then
    raise exception 'Invalid status transition';
  end if;

  should_release_stock := target_status in ('cancelled','refunded') and order_row.stock_released_at is null;

  if should_release_stock then
    for item in
      select variant_id, quantity
      from public.merchandise_order_items
      where order_id = target_order_id
        and variant_id is not null
    loop
      update public.merchandise_variants
      set stock_quantity = stock_quantity + item.quantity,
          updated_at = now()
      where id = item.variant_id;
    end loop;
  end if;

  update public.merchandise_orders
  set status = target_status,
      paid_at = case when target_status = 'paid' and paid_at is null then now() else paid_at end,
      stock_released_at = case when should_release_stock then now() else stock_released_at end,
      updated_at = now()
  where id = target_order_id;

  insert into public.merchandise_order_status_history (order_id, old_status, new_status, changed_by, reason)
  values (target_order_id, order_row.status, target_status, auth.uid(), change_reason);

  insert into public.notifications (recipient_id, title, body, related_entity_type, related_entity_id)
  values (
    order_row.customer_id,
    'Merchandise order updated',
    'Order ' || order_row.order_number || ' is now ' || replace(target_status, '_', ' ') || '.',
    'merchandise_order',
    target_order_id
  );

  perform app_private.write_audit_log(
    'merchandise.order_status_changed',
    'merchandise_order',
    target_order_id,
    jsonb_build_object('status', order_row.status),
    jsonb_build_object('status', target_status),
    change_reason
  );

  return query select target_order_id, order_row.order_number, order_row.status, target_status, order_row.customer_id;
end;
$$;

create or replace function public.create_merchandise_order(
  target_variant_id uuid,
  order_quantity int default 1,
  target_pickup_or_delivery text default 'pickup',
  target_notes text default null
)
returns table (
  order_id uuid,
  order_number text,
  order_status text,
  total_cents int
)
language sql
security invoker
set search_path = public, extensions
as $$
  select *
  from app_private.create_merchandise_order(target_variant_id, order_quantity, target_pickup_or_delivery, target_notes);
$$;

create or replace function public.update_merchandise_order_state(
  target_order_id uuid,
  target_status text,
  change_reason text default null
)
returns table (
  order_id uuid,
  order_number text,
  old_status text,
  new_status text,
  customer_id uuid
)
language sql
security invoker
set search_path = public, extensions
as $$
  select *
  from app_private.update_merchandise_order_state(target_order_id, target_status, change_reason);
$$;

revoke all on function app_private.create_merchandise_order(uuid, int, text, text) from public;
revoke all on function public.create_merchandise_order(uuid, int, text, text) from public;
revoke all on function app_private.update_merchandise_order_state(uuid, text, text) from public;
revoke all on function public.update_merchandise_order_state(uuid, text, text) from public;

grant execute on function app_private.create_merchandise_order(uuid, int, text, text) to authenticated;
grant execute on function public.create_merchandise_order(uuid, int, text, text) to authenticated;
grant execute on function app_private.update_merchandise_order_state(uuid, text, text) to authenticated;
grant execute on function public.update_merchandise_order_state(uuid, text, text) to authenticated;

grant select on public.merchandise_order_items to authenticated;
grant select on public.merchandise_order_status_history to authenticated;
grant select, insert, update, delete on public.merchandise_order_items to service_role;
grant select, insert, update, delete on public.merchandise_order_status_history to service_role;
