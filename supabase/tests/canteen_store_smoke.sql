begin;

do $$
begin
  if has_function_privilege('anon', 'public.checkout_canteen_cart(text,uuid,integer,uuid[],uuid,text)', 'execute') then
    raise exception 'anon must not execute canteen checkout';
  end if;
  if not has_function_privilege('authenticated', 'public.checkout_canteen_cart(text,uuid,integer,uuid[],uuid,text)', 'execute') then
    raise exception 'authenticated users must execute canteen checkout';
  end if;
end;
$$;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('00000000-0000-4000-8000-000000000881','00000000-0000-0000-0000-000000000000','authenticated','authenticated','canteen-store-test@example.invalid','',now(),'{"provider":"email","providers":["email"]}','{"full_name":"Canteen Store Test"}',now(),now());

insert into public.canteen_categories(id,name,display_order,is_active)
values ('00000000-0000-4000-8000-000000000882','Test menu',1,true);
insert into public.canteen_products(id,category_id,name,description,price_cents,stock_quantity,is_active,is_sold_out,max_quantity_per_order)
values ('00000000-0000-4000-8000-000000000883','00000000-0000-4000-8000-000000000882','Test snack','Transactional canteen test item',450,2,true,false,2);

select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000881","role":"authenticated"}',true);
set local role authenticated;
select public.set_canteen_cart_item('00000000-0000-4000-8000-000000000883',2,false);
select * from public.checkout_canteen_cart('canteen-smoke-test-request-0001',null,0,'{}'::uuid[],null,null);

do $$
declare placed public.canteen_orders%rowtype;
begin
  select * into placed from public.canteen_orders where customer_id=auth.uid() and idempotency_key='canteen-smoke-test-request-0001';
  if placed.payment_status <> 'awaiting_payment' or placed.payment_method <> 'pay_at_club' or placed.amount_due_cents <> 900 then raise exception 'pay-at-club state is incorrect'; end if;
  if placed.subtotal_cents <> 900 or placed.total_cents <> 900 then raise exception 'server total is incorrect'; end if;
  if exists(select 1 from public.canteen_cart_items where user_id=auth.uid()) then raise exception 'cart was not cleared'; end if;
  if (select stock_quantity from public.canteen_products where id='00000000-0000-4000-8000-000000000883') <> 0 then raise exception 'stock was not decremented'; end if;
  if (select count(*) from public.canteen_order_items where order_id=placed.id) <> 1 then raise exception 'order item was not created'; end if;
end;
$$;
rollback;
