insert into public.permissions(key,name,description) values
('shop.products.view','View shop products','View unified canteen and merchandise products'),
('shop.products.manage','Manage shop products','Manage unified shop catalogue and media'),
('shop.orders.view','View shop orders','View shop orders and operational exports'),
('shop.orders.manage','Manage shop orders','Manage payment and fulfilment status'),
('shop.canteen.scan','Scan canteen collections','View canteen collection vouchers'),
('shop.canteen.redeem','Redeem canteen collections','Atomically collect canteen orders'),
('shop.merchandise.fulfil','Fulfil merchandise','Prepare and collect merchandise orders')
on conflict(key) do update set name=excluded.name,description=excluded.description;

alter table public.canteen_products add column if not exists image_object_key text,add column if not exists available_from timestamptz,add column if not exists available_until timestamptz,add column if not exists sort_order int not null default 100;
alter table public.merchandise_products add column if not exists image_object_key text,add column if not exists available_from timestamptz,add column if not exists available_until timestamptz,add column if not exists sort_order int not null default 100;

create table public.shop_cart_items(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id) on delete cascade,
 product_type text not null check(product_type in('canteen','merchandise')),
 canteen_product_id uuid references public.canteen_products(id) on delete cascade,
 merchandise_variant_id uuid references public.merchandise_variants(id) on delete cascade,
 quantity int not null check(quantity between 1 and 50),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check((product_type='canteen' and canteen_product_id is not null and merchandise_variant_id is null) or(product_type='merchandise' and merchandise_variant_id is not null and canteen_product_id is null))
);
create unique index shop_cart_canteen_unique on public.shop_cart_items(user_id,canteen_product_id) where canteen_product_id is not null;
create unique index shop_cart_merch_unique on public.shop_cart_items(user_id,merchandise_variant_id) where merchandise_variant_id is not null;
create table public.shop_orders(
 id uuid primary key default gen_random_uuid(),order_number text not null unique,user_id uuid not null references public.profiles(id) on delete restrict,
 status text not null default 'pending_payment' check(status in('pending_payment','confirmed','partially_ready','ready','completed','cancelled','expired','refunded')),
 payment_status text not null default 'pending' check(payment_status in('not_required','pending','paid','failed','cancelled','refunded')),
 currency text not null default 'AUD',subtotal_cents int not null check(subtotal_cents>=0),total_cents int not null check(total_cents>=0),
 payment_provider text,payment_id uuid references public.payments(id) on delete set null,idempotency_key text not null unique,
 completed_at timestamptz,cancelled_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table public.shop_order_items(
 id uuid primary key default gen_random_uuid(),order_id uuid not null references public.shop_orders(id) on delete cascade,
 product_type text not null check(product_type in('canteen','merchandise')),canteen_product_id uuid references public.canteen_products(id) on delete set null,
 merchandise_variant_id uuid references public.merchandise_variants(id) on delete set null,product_name_snapshot text not null,variant_name_snapshot text,
 category_snapshot text not null,quantity int not null check(quantity>0),unit_price_cents int not null check(unit_price_cents>=0),line_total_cents int not null check(line_total_cents>=0),
 fulfilment_type text not null check(fulfilment_type in('canteen_collection','merchandise_collection')),
 status text not null default 'awaiting_confirmation' check(status in('awaiting_confirmation','order_received','preparing','ready','collected','cancelled','refunded')),created_at timestamptz not null default now()
);
create table public.shop_fulfilments(
 id uuid primary key default gen_random_uuid(),order_id uuid not null references public.shop_orders(id) on delete cascade,user_id uuid not null references public.profiles(id) on delete restrict,
 fulfilment_type text not null check(fulfilment_type in('canteen_collection','merchandise_collection')),
 display_code text not null unique,token_hash text not null unique,status text not null default 'active' check(status in('active','ready','collected','cancelled')),
 collected_at timestamptz,collected_by uuid references public.profiles(id) on delete set null,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(order_id,fulfilment_type)
);
create index shop_orders_user_idx on public.shop_orders(user_id,created_at desc);
create index shop_order_items_order_idx on public.shop_order_items(order_id,product_type,status);
create index shop_fulfilments_user_idx on public.shop_fulfilments(user_id,status,created_at desc);
create trigger shop_cart_updated before update on public.shop_cart_items for each row execute function app_private.set_updated_at();
create trigger shop_orders_updated before update on public.shop_orders for each row execute function app_private.set_updated_at();
create trigger shop_fulfilments_updated before update on public.shop_fulfilments for each row execute function app_private.set_updated_at();

alter table public.shop_cart_items enable row level security;alter table public.shop_orders enable row level security;alter table public.shop_order_items enable row level security;alter table public.shop_fulfilments enable row level security;
create policy shop_cart_owner on public.shop_cart_items for all to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create policy shop_orders_owner_read on public.shop_orders for select to authenticated using(user_id=(select auth.uid()) or app_private.has_permission('shop.orders.view') or app_private.has_permission('shop.orders.manage'));
create policy shop_items_owner_read on public.shop_order_items for select to authenticated using(exists(select 1 from public.shop_orders o where o.id=order_id and(o.user_id=(select auth.uid()) or app_private.has_permission('shop.orders.view') or app_private.has_permission('shop.orders.manage'))));
create policy shop_fulfilments_owner_read on public.shop_fulfilments for select to authenticated using(user_id=(select auth.uid()) or app_private.has_permission('shop.canteen.scan') or app_private.has_permission('shop.canteen.redeem') or app_private.has_permission('shop.merchandise.fulfil') or app_private.has_permission('shop.orders.manage'));
grant select,insert,update,delete on public.shop_cart_items to authenticated;grant select on public.shop_orders,public.shop_order_items,public.shop_fulfilments to authenticated;grant all on public.shop_cart_items,public.shop_orders,public.shop_order_items,public.shop_fulfilments to service_role;

create or replace function app_private.confirm_shop_order(target uuid) returns int language plpgsql security definer set search_path=public,app_private,extensions as $$
declare o public.shop_orders%rowtype; code text; count_items int;
begin
 select * into o from public.shop_orders where id=target for update;if not found then raise exception 'Order not found';end if;
 if o.status in('confirmed','partially_ready','ready','completed') then return(select count(*) from public.shop_order_items where order_id=o.id);end if;
 if o.total_cents>0 and o.payment_status<>'paid' then raise exception 'Payment not confirmed';end if;
 update public.shop_order_items set status=case when product_type='canteen' then 'ready' else 'order_received' end where order_id=o.id;
 if exists(select 1 from public.shop_order_items where order_id=o.id and product_type='canteen') then code:='SC'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));insert into public.shop_fulfilments(order_id,user_id,fulfilment_type,display_code,token_hash,status) values(o.id,o.user_id,'canteen_collection',code,encode(digest(code,'sha256'),'hex'),'ready') on conflict(order_id,fulfilment_type) do nothing;end if;
 update public.shop_orders set status=case when exists(select 1 from public.shop_order_items where order_id=o.id and product_type='merchandise') then 'confirmed' else 'ready' end,payment_status=case when total_cents=0 then 'not_required' else 'paid' end where id=o.id;
 insert into public.notifications(recipient_id,title,body,related_entity_type,related_entity_id) values(o.user_id,'Club shop order confirmed','Your order is confirmed. Check My orders and your wallet for collection details.','shop_order',o.id);
 select count(*) into count_items from public.shop_order_items where order_id=o.id;perform app_private.write_audit_log('shop.order_confirmed','shop_order',o.id,null,jsonb_build_object('items',count_items),null);return count_items;
end $$;

create or replace function public.checkout_shop_cart(request_key text,payment_provider text default 'manual') returns table(order_id uuid,order_status text,payment_status text,total_cents int,payment_id uuid)
language plpgsql security definer set search_path=public,app_private,extensions as $$
declare c record;oid uuid;pid uuid;total int:=0;price int;label text;name text;category text;stock int;code text;
begin
 if auth.uid() is null then raise exception 'Authentication required';end if;
 if not exists(select 1 from public.shop_cart_items where user_id=auth.uid()) then raise exception 'Your cart is empty';end if;
 insert into public.shop_orders(order_number,user_id,subtotal_cents,total_cents,payment_provider,idempotency_key) values('SHOP-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),auth.uid(),0,0,payment_provider,request_key) on conflict(idempotency_key) do update set idempotency_key=excluded.idempotency_key returning id into oid;
 for c in select * from public.shop_cart_items where user_id=auth.uid() order by created_at for update loop
  if c.product_type='canteen' then
   select p.price_cents,p.name,'Canteen',p.stock_quantity into price,name,category,stock from public.canteen_products p where p.id=c.canteen_product_id and p.is_active and not p.is_sold_out and(p.available_from is null or p.available_from<=now())and(p.available_until is null or p.available_until>now()) for update;
   if not found then raise exception 'A canteen product is no longer available';end if;if stock is not null and stock<c.quantity then raise exception 'Not enough canteen stock remains';end if;
   if stock is not null then update public.canteen_products set stock_quantity=stock-c.quantity where id=c.canteen_product_id;end if;label:=null;
  else
   select coalesce(v.sale_price_cents,v.price_cents),p.name,coalesce(v.size,'')||case when v.size is not null and v.colour is not null then ' / ' else '' end||coalesce(v.colour,''),'Club merchandise',v.stock_quantity into price,name,label,category,stock from public.merchandise_variants v join public.merchandise_products p on p.id=v.product_id where v.id=c.merchandise_variant_id and v.is_active and p.status='active' and(p.available_from is null or p.available_from<=now())and(p.available_until is null or p.available_until>now()) for update;
   if not found then raise exception 'A merchandise product is no longer available';end if;if stock<c.quantity then raise exception 'Not enough merchandise stock remains';end if;update public.merchandise_variants set stock_quantity=stock-c.quantity where id=c.merchandise_variant_id;
  end if;
  insert into public.shop_order_items(order_id,product_type,canteen_product_id,merchandise_variant_id,product_name_snapshot,variant_name_snapshot,category_snapshot,quantity,unit_price_cents,line_total_cents,fulfilment_type) values(oid,c.product_type,c.canteen_product_id,c.merchandise_variant_id,name,nullif(label,''),category,c.quantity,price,price*c.quantity,case when c.product_type='canteen' then 'canteen_collection' else 'merchandise_collection' end);
  total:=total+price*c.quantity;
 end loop;
 update public.shop_orders set subtotal_cents=total,total_cents=total,payment_status=case when total=0 then 'not_required' else 'pending' end where id=oid;
 if total=0 then perform app_private.confirm_shop_order(oid);delete from public.shop_cart_items where user_id=auth.uid();
 else insert into public.payments(provider,payer_id,beneficiary_id,amount_cents,currency,status,idempotency_key,metadata) values(payment_provider,auth.uid(),auth.uid(),total,'AUD','created','shop-order:'||oid,jsonb_build_object('purpose','shop_order','shop_order_id',oid)) returning id into pid;update public.shop_orders set payment_id=pid where id=oid;end if;
 perform app_private.write_audit_log('shop.order_created','shop_order',oid,null,jsonb_build_object('total_cents',total),null);
 return query select oid,(select status from public.shop_orders where id=oid),(select shop_orders.payment_status from public.shop_orders where id=oid),total,pid;
end $$;
revoke all on function public.checkout_shop_cart(text,text) from public,anon;grant execute on function public.checkout_shop_cart(text,text) to authenticated;

create or replace function app_private.complete_shop_payment() returns trigger language plpgsql security definer set search_path=public,app_private as $$
declare oid uuid;begin if new.metadata->>'purpose'='shop_order' and old.status is distinct from new.status then oid:=(new.metadata->>'shop_order_id')::uuid;if new.status='succeeded' then update public.shop_orders set payment_status='paid' where id=oid;perform app_private.confirm_shop_order(oid);delete from public.shop_cart_items where user_id=new.payer_id;elsif new.status in('failed','cancelled') then update public.shop_orders set payment_status=new.status,status='cancelled',cancelled_at=now() where id=oid and status='pending_payment';end if;end if;return new;end $$;
create trigger payments_complete_shop_order after update of status on public.payments for each row execute function app_private.complete_shop_payment();

create or replace function public.redeem_shop_collection(collection_code text) returns table(fulfilment_id uuid,result text,order_number text,collected_at timestamptz) language plpgsql security definer set search_path=public,app_private,extensions as $$
declare f public.shop_fulfilments%rowtype;begin if auth.uid() is null or not app_private.has_permission('shop.canteen.redeem') then raise exception 'Not authorised';end if;select * into f from public.shop_fulfilments where token_hash=encode(digest(trim(collection_code),'sha256'),'hex') for update;if not found then raise exception 'Collection voucher not found';end if;if f.status='collected' then perform app_private.write_audit_log('shop.collection_duplicate','shop_fulfilment',f.id,null,null,null);return query select f.id,'already_collected',o.order_number,f.collected_at from public.shop_orders o where o.id=f.order_id;return;end if;if f.status not in('active','ready') then raise exception 'Collection is not available';end if;update public.shop_fulfilments set status='collected',collected_at=now(),collected_by=auth.uid() where id=f.id returning shop_fulfilments.collected_at into f.collected_at;update public.shop_order_items set status='collected' where order_id=f.order_id and fulfilment_type=f.fulfilment_type;perform app_private.write_audit_log('shop.canteen_collected','shop_fulfilment',f.id,null,jsonb_build_object('collected_at',f.collected_at),null);return query select f.id,'collected',o.order_number,f.collected_at from public.shop_orders o where o.id=f.order_id;end $$;
revoke all on function public.redeem_shop_collection(text) from public,anon;grant execute on function public.redeem_shop_collection(text) to authenticated;
