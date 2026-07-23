-- Canteen catalogue fulfilment modes, protected order transitions and purchased item vouchers.

alter table public.canteen_products
add column if not exists fulfilment_type text not null default 'direct_order'
  check (fulfilment_type in ('direct_order', 'item_voucher')),
add column if not exists stock_quantity int check (stock_quantity is null or stock_quantity >= 0),
add column if not exists low_stock_threshold int not null default 5 check (low_stock_threshold >= 0),
add column if not exists voucher_valid_days int not null default 14 check (voucher_valid_days > 0);

alter table public.canteen_order_items
add column if not exists fulfilment_type_snapshot text not null default 'direct_order'
  check (fulfilment_type_snapshot in ('direct_order', 'item_voucher')),
add column if not exists voucher_issuance_id uuid references public.voucher_issuances(id) on delete set null;

alter table public.canteen_orders
add column if not exists pickup_code text unique,
add column if not exists pickup_token_hash text unique;

create index if not exists canteen_products_fulfilment_active_idx
on public.canteen_products (fulfilment_type, is_active, is_sold_out, display_order);

create index if not exists canteen_orders_status_payment_created_idx
on public.canteen_orders (order_status, payment_status, created_at);

create index if not exists canteen_order_items_order_fulfilment_idx
on public.canteen_order_items (order_id, fulfilment_type_snapshot);

create or replace function app_private.issue_canteen_order_vouchers(target_order_id uuid)
returns int
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  order_row public.canteen_orders%rowtype;
  item record;
  raw_code text;
  voucher_id uuid;
  issued_count int := 0;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select *
  into order_row
  from public.canteen_orders
  where id = target_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if order_row.payment_status <> 'paid' then
    return 0;
  end if;

  for item in
    select coi.id, coi.product_id, coi.product_name_snapshot, coi.quantity, coi.line_total_cents, cp.voucher_valid_days
    from public.canteen_order_items coi
    left join public.canteen_products cp on cp.id = coi.product_id
    where coi.order_id = target_order_id
      and coi.fulfilment_type_snapshot = 'item_voucher'
      and coi.voucher_issuance_id is null
  loop
    raw_code := upper(replace(gen_random_uuid()::text, '-', ''));

    insert into public.voucher_issuances (
      redemption_code,
      token_hash,
      beneficiary_id,
      issued_by,
      issue_reason,
      voucher_type,
      original_value_cents,
      remaining_value_cents,
      allowed_product_ids,
      expires_at,
      redemption_limit,
      status
    )
    values (
      raw_code,
      encode(extensions.digest(raw_code, 'sha256'), 'hex'),
      coalesce(order_row.recipient_id, order_row.customer_id),
      auth.uid(),
      item.product_name_snapshot || ' voucher from order ' || order_row.order_number,
      'specific_product',
      item.line_total_cents,
      item.line_total_cents,
      case when item.product_id is null then '{}'::uuid[] else array[item.product_id] end,
      now() + make_interval(days => coalesce(item.voucher_valid_days, 14)),
      greatest(item.quantity, 1),
      'active'
    )
    returning id into voucher_id;

    update public.canteen_order_items
    set voucher_issuance_id = voucher_id
    where id = item.id;

    insert into public.notifications (recipient_id, title, body, related_entity_type, related_entity_id)
    values (
      coalesce(order_row.recipient_id, order_row.customer_id),
      'Canteen voucher ready',
      item.product_name_snapshot || ' has been added to your wallet.',
      'voucher',
      voucher_id
    );

    issued_count := issued_count + 1;
  end loop;

  return issued_count;
end;
$$;

create or replace function app_private.update_canteen_order_state(
  target_order_id uuid,
  target_order_status text default null,
  target_payment_status text default null,
  change_reason text default null
)
returns table (
  order_id uuid,
  order_number text,
  old_order_status text,
  new_order_status text,
  old_payment_status text,
  new_payment_status text,
  customer_id uuid,
  recipient_id uuid,
  issued_vouchers int
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  order_row public.canteen_orders%rowtype;
  next_order_status text;
  next_payment_status text;
  issued_count int := 0;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not app_private.has_permission('canteen.orders.manage') then
    raise exception 'Worker not authorised';
  end if;

  select *
  into order_row
  from public.canteen_orders
  where id = target_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  next_order_status := coalesce(target_order_status, order_row.order_status);
  next_payment_status := coalesce(target_payment_status, order_row.payment_status);

  if next_order_status not in ('accepted','preparing','ready_for_pickup','collected','cancelled','refunded','partially_refunded','expired') then
    raise exception 'Invalid order status';
  end if;

  if next_payment_status not in ('unpaid','awaiting_payment','paid','partially_refunded','refunded') then
    raise exception 'Invalid payment status';
  end if;

  if order_row.order_status in ('collected','cancelled','refunded','expired') and next_order_status <> order_row.order_status then
    raise exception 'Closed orders cannot be moved';
  end if;

  if order_row.order_status = 'accepted' and next_order_status not in ('accepted','preparing','ready_for_pickup','cancelled') then
    raise exception 'Invalid status transition';
  end if;

  if order_row.order_status = 'preparing' and next_order_status not in ('preparing','ready_for_pickup','cancelled') then
    raise exception 'Invalid status transition';
  end if;

  if order_row.order_status = 'ready_for_pickup' and next_order_status not in ('ready_for_pickup','collected') then
    raise exception 'Invalid status transition';
  end if;

  update public.canteen_orders
  set order_status = next_order_status,
      payment_status = next_payment_status,
      pickup_code = coalesce(pickup_code, 'GEORDER:' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))),
      updated_at = now()
  where id = target_order_id;

  insert into public.order_status_history (order_id, old_status, new_status, changed_by, reason)
  values (target_order_id, order_row.order_status, next_order_status, auth.uid(), change_reason);

  if next_payment_status = 'paid' then
    issued_count := app_private.issue_canteen_order_vouchers(target_order_id);
  end if;

  return query
  select target_order_id, order_row.order_number, order_row.order_status, next_order_status,
         order_row.payment_status, next_payment_status, order_row.customer_id, order_row.recipient_id, issued_count;
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
    venue_id,
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
    target_venue_id,
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

create or replace function public.create_canteen_order(
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
language sql
security invoker
set search_path = public, extensions
as $$
  select *
  from app_private.create_canteen_order(
    target_product_id,
    target_venue_id,
    target_beneficiary_id,
    order_quantity,
    target_pickup_window_start,
    target_special_instructions
  );
$$;

create or replace function public.update_canteen_order_state(
  target_order_id uuid,
  target_order_status text default null,
  target_payment_status text default null,
  change_reason text default null
)
returns table (
  order_id uuid,
  order_number text,
  old_order_status text,
  new_order_status text,
  old_payment_status text,
  new_payment_status text,
  customer_id uuid,
  recipient_id uuid,
  issued_vouchers int
)
language sql
security invoker
set search_path = public, extensions
as $$
  select *
  from app_private.update_canteen_order_state(target_order_id, target_order_status, target_payment_status, change_reason);
$$;

revoke all on function app_private.issue_canteen_order_vouchers(uuid) from public;
revoke all on function app_private.create_canteen_order(uuid, uuid, uuid, int, timestamptz, text) from public;
revoke all on function public.create_canteen_order(uuid, uuid, uuid, int, timestamptz, text) from public;
revoke all on function app_private.update_canteen_order_state(uuid, text, text, text) from public;
revoke all on function public.update_canteen_order_state(uuid, text, text, text) from public;

grant execute on function app_private.issue_canteen_order_vouchers(uuid) to authenticated;
grant execute on function app_private.create_canteen_order(uuid, uuid, uuid, int, timestamptz, text) to authenticated;
grant execute on function public.create_canteen_order(uuid, uuid, uuid, int, timestamptz, text) to authenticated;
grant execute on function app_private.update_canteen_order_state(uuid, text, text, text) to authenticated;
grant execute on function public.update_canteen_order_state(uuid, text, text, text) to authenticated;
