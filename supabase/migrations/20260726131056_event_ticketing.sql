insert into public.permissions(key,name,description) values
('events.tickets.scan','Scan event tickets','View event ticket details at entry'),
('events.tickets.redeem','Redeem event tickets','Atomically redeem event tickets'),
('events.orders.read','View event orders','View event ticket orders and attendee exports')
on conflict(key) do update set name=excluded.name,description=excluded.description;

alter table public.club_events
  add column if not exists image_object_key text,
  add column if not exists per_user_ticket_limit int check(per_user_ticket_limit is null or per_user_ticket_limit > 0),
  add column if not exists instructions text,
  add column if not exists cancellation_notes text;

create table public.club_event_ticket_types(
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references public.club_events(id) on delete cascade,
 name text not null check(char_length(name) between 2 and 120),
 description text check(char_length(description)<=500),
 price_cents int not null default 0 check(price_cents>=0),
 currency text not null default 'AUD' check(currency ~ '^[A-Z]{3}$'),
 capacity int check(capacity is null or capacity>0),
 max_per_order int not null default 10 check(max_per_order between 1 and 50),
 sales_open_at timestamptz,
 sales_close_at timestamptz,
 active boolean not null default true,
 sort_order int not null default 100 check(sort_order between 0 and 10000),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 created_by uuid references public.profiles(id) on delete set null,
 updated_by uuid references public.profiles(id) on delete set null,
 unique(event_id,name)
);
create table public.club_event_orders(
 id uuid primary key default gen_random_uuid(), order_number text not null unique,
 user_id uuid not null references public.profiles(id) on delete restrict,
 event_id uuid not null references public.club_events(id) on delete restrict,
 status text not null check(status in('pending_payment','completed','cancelled','expired','refunded')) default 'pending_payment',
 payment_status text not null check(payment_status in('not_required','pending','paid','failed','cancelled','refunded')) default 'pending',
 currency text not null default 'AUD', subtotal_cents int not null check(subtotal_cents>=0), total_cents int not null check(total_cents>=0),
 payment_provider text, payment_id uuid references public.payments(id) on delete set null,
 idempotency_key text not null unique, reservation_expires_at timestamptz,
 completed_at timestamptz, cancelled_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.club_event_order_items(
 id uuid primary key default gen_random_uuid(), order_id uuid not null references public.club_event_orders(id) on delete cascade,
 ticket_type_id uuid not null references public.club_event_ticket_types(id) on delete restrict,
 ticket_name text not null, quantity int not null check(quantity between 1 and 50),
 unit_price_cents int not null check(unit_price_cents>=0), line_total_cents int not null check(line_total_cents>=0),
 created_at timestamptz not null default now(), unique(order_id,ticket_type_id)
);
alter table public.voucher_issuances drop constraint if exists voucher_issuances_voucher_type_check;
alter table public.voucher_issuances add constraint voucher_issuances_voucher_type_check
check(voucher_type in('fixed_amount','specific_product','category','meal_deal','declining_balance','event_ticket'));
create table public.club_event_tickets(
 id uuid primary key default gen_random_uuid(), order_id uuid not null references public.club_event_orders(id) on delete restrict,
 order_item_id uuid not null references public.club_event_order_items(id) on delete restrict,
 event_id uuid not null references public.club_events(id) on delete restrict,
 ticket_type_id uuid not null references public.club_event_ticket_types(id) on delete restrict,
 owner_user_id uuid not null references public.profiles(id) on delete restrict,
 voucher_id uuid not null unique references public.voucher_issuances(id) on delete restrict,
 ticket_code text not null unique,
 status text not null default 'valid' check(status in('valid','redeemed','cancelled','refunded')),
 issued_at timestamptz not null default now(), redeemed_at timestamptz, redeemed_by uuid references public.profiles(id) on delete set null,
 cancelled_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index club_event_ticket_types_public_idx on public.club_event_ticket_types(event_id,sort_order) where active;
create index club_event_orders_user_idx on public.club_event_orders(user_id,created_at desc);
create index club_event_orders_event_idx on public.club_event_orders(event_id,status,payment_status);
create index club_event_tickets_owner_idx on public.club_event_tickets(owner_user_id,event_id,issued_at desc);
create index club_event_tickets_event_status_idx on public.club_event_tickets(event_id,ticket_type_id,status);

create trigger club_event_ticket_types_updated before update on public.club_event_ticket_types for each row execute function app_private.set_updated_at();
create trigger club_event_orders_updated before update on public.club_event_orders for each row execute function app_private.set_updated_at();
create trigger club_event_tickets_updated before update on public.club_event_tickets for each row execute function app_private.set_updated_at();

alter table public.club_event_ticket_types enable row level security;
alter table public.club_event_orders enable row level security;
alter table public.club_event_order_items enable row level security;
alter table public.club_event_tickets enable row level security;
create policy event_ticket_types_read on public.club_event_ticket_types for select to anon,authenticated
using(active and exists(select 1 from public.club_events e where e.id=event_id and e.status='active' and e.visibility in('public','members')));
create policy event_ticket_types_admin on public.club_event_ticket_types for all to authenticated using(app_private.has_permission('events.manage')) with check(app_private.has_permission('events.manage'));
create policy event_orders_owner_read on public.club_event_orders for select to authenticated using(user_id=(select auth.uid()) or app_private.has_permission('events.orders.read') or app_private.has_permission('events.manage'));
create policy event_order_items_owner_read on public.club_event_order_items for select to authenticated using(exists(select 1 from public.club_event_orders o where o.id=order_id and(o.user_id=(select auth.uid()) or app_private.has_permission('events.orders.read') or app_private.has_permission('events.manage'))));
create policy event_tickets_owner_read on public.club_event_tickets for select to authenticated using(owner_user_id=(select auth.uid()) or app_private.has_permission('events.tickets.scan') or app_private.has_permission('events.tickets.redeem') or app_private.has_permission('events.manage'));
grant select on public.club_event_ticket_types to anon,authenticated;
grant select on public.club_event_orders,public.club_event_order_items,public.club_event_tickets to authenticated;
grant all on public.club_event_ticket_types,public.club_event_orders,public.club_event_order_items,public.club_event_tickets to service_role;

create or replace function app_private.issue_event_order(target_order uuid) returns int language plpgsql security definer set search_path=public,app_private,extensions as $$
declare o public.club_event_orders%rowtype; i record; n int; code text; vh text; v_id uuid; issued int:=0;
begin
 select * into o from public.club_event_orders where id=target_order for update;
 if not found then raise exception 'Order not found'; end if;
 if o.status='completed' then return (select count(*) from public.club_event_tickets where order_id=o.id); end if;
 if o.total_cents>0 and o.payment_status<>'paid' then raise exception 'Payment has not been confirmed'; end if;
 for i in select * from public.club_event_order_items where order_id=o.id loop
   for n in 1..i.quantity loop
     code:=upper(substr(replace(gen_random_uuid()::text,'-',''),1,14)); vh:=encode(digest(code,'sha256'),'hex');
     insert into public.voucher_issuances(token_hash,redemption_code,beneficiary_id,issued_by,issue_reason,voucher_type,original_value_cents,remaining_value_cents,valid_from,expires_at,status)
     select vh,code,o.user_id,o.user_id,'Event ticket: '||e.title||' — '||i.ticket_name,'event_ticket',0,0,now(),e.ends_at,'active' from public.club_events e where e.id=o.event_id returning id into v_id;
     insert into public.club_event_tickets(order_id,order_item_id,event_id,ticket_type_id,owner_user_id,voucher_id,ticket_code) values(o.id,i.id,o.event_id,i.ticket_type_id,o.user_id,v_id,code);
     issued:=issued+1;
   end loop;
 end loop;
 update public.club_event_orders set status='completed',payment_status=case when total_cents=0 then 'not_required' else 'paid' end,completed_at=now() where id=o.id;
 insert into public.notifications(recipient_id,title,body,related_entity_type,related_entity_id) values(o.user_id,'Event tickets ready','Your event tickets are now available in your wallet.','club_event_order',o.id);
 perform app_private.write_audit_log('event.tickets_issued','club_event_order',o.id,null,jsonb_build_object('ticket_count',issued),null);
 return issued;
end $$;

create or replace function public.create_event_ticket_order(ticket_type uuid,ticket_quantity int,request_key text,payment_provider text default 'manual')
returns table(order_id uuid,order_status text,payment_status text,total_cents int,payment_id uuid)
language plpgsql security definer set search_path=public,app_private,extensions as $$
declare t public.club_event_ticket_types%rowtype; e public.club_events%rowtype; oid uuid; pid uuid; sold int; held int; owned int; total int;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if ticket_quantity<1 then raise exception 'Choose at least one ticket'; end if;
 select * into t from public.club_event_ticket_types where id=ticket_type and active for update;
 if not found then raise exception 'Ticket type unavailable'; end if;
 select * into e from public.club_events where id=t.event_id for update;
 if e.status<>'active' or e.visibility='private' then raise exception 'Event unavailable'; end if;
 if e.registration_opens_at is not null and e.registration_opens_at>now() then raise exception 'Ticket sales are not open'; end if;
 if e.registration_closes_at is not null and e.registration_closes_at<=now() then raise exception 'Ticket sales are closed'; end if;
 if e.starts_at<=now() then raise exception 'This event has started'; end if;
 if ticket_quantity>t.max_per_order then raise exception 'Ticket quantity exceeds the order limit'; end if;
 select count(*) into sold from public.club_event_tickets where ticket_type_id=t.id and status in('valid','redeemed');
 select coalesce(sum(i.quantity),0) into held from public.club_event_order_items i join public.club_event_orders o on o.id=i.order_id where i.ticket_type_id=t.id and o.status='pending_payment' and o.reservation_expires_at>now();
 if t.capacity is not null and sold+held+ticket_quantity>t.capacity then raise exception 'Not enough tickets remain'; end if;
 select count(*) into owned from public.club_event_tickets where owner_user_id=auth.uid() and event_id=e.id and status in('valid','redeemed');
 if e.per_user_ticket_limit is not null and owned+ticket_quantity>e.per_user_ticket_limit then raise exception 'Your ticket limit has been reached'; end if;
 total:=t.price_cents*ticket_quantity;
 insert into public.club_event_orders(order_number,user_id,event_id,status,payment_status,currency,subtotal_cents,total_cents,payment_provider,idempotency_key,reservation_expires_at)
 values('EV-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),auth.uid(),e.id,case when total=0 then 'pending_payment' else 'pending_payment' end,case when total=0 then 'not_required' else 'pending' end,t.currency,total,total,payment_provider,request_key,case when total>0 then now()+interval '30 minutes' end)
 on conflict(idempotency_key) do update set idempotency_key=excluded.idempotency_key returning id into oid;
 insert into public.club_event_order_items(order_id,ticket_type_id,ticket_name,quantity,unit_price_cents,line_total_cents) values(oid,t.id,t.name,ticket_quantity,t.price_cents,total) on conflict on constraint club_event_order_items_order_id_ticket_type_id_key do nothing;
 if total=0 then perform app_private.issue_event_order(oid);
 else
   insert into public.payments(provider,payer_id,beneficiary_id,amount_cents,currency,status,idempotency_key,metadata)
   values(payment_provider,auth.uid(),auth.uid(),total,t.currency,'created','event-order:'||oid,jsonb_build_object('purpose','event_ticket','event_order_id',oid)) returning id into pid;
   update public.club_event_orders set payment_id=pid where id=oid;
   perform app_private.write_audit_log('event.paid_order_created','club_event_order',oid,null,jsonb_build_object('total_cents',total,'provider',payment_provider),null);
 end if;
 return query select oid,(select status from public.club_event_orders where id=oid),(select club_event_orders.payment_status from public.club_event_orders where id=oid),total,pid;
end $$;
revoke all on function public.create_event_ticket_order(uuid,int,text,text) from public;
grant execute on function public.create_event_ticket_order(uuid,int,text,text) to authenticated;

create or replace function app_private.complete_event_payment() returns trigger language plpgsql security definer set search_path=public,app_private as $$
declare oid uuid;
begin
 if new.status='succeeded' and old.status is distinct from new.status and new.metadata->>'purpose'='event_ticket' then
   oid:=(new.metadata->>'event_order_id')::uuid;
   update public.club_event_orders set payment_status='paid' where id=oid;
   perform app_private.issue_event_order(oid);
 elsif new.status in('failed','cancelled') and new.metadata->>'purpose'='event_ticket' then
   oid:=(new.metadata->>'event_order_id')::uuid;
   update public.club_event_orders set payment_status=new.status,status='cancelled',cancelled_at=now() where id=oid and status='pending_payment';
 end if; return new;
end $$;
create trigger payments_complete_event_ticket after update of status on public.payments for each row execute function app_private.complete_event_payment();

create or replace function public.redeem_event_ticket(redemption_code text) returns table(ticket_id uuid,result text,event_title text,ticket_type text,redeemed_at timestamptz)
language plpgsql security definer set search_path=public,app_private,extensions as $$
declare t public.club_event_tickets%rowtype;
begin
 if auth.uid() is null or not app_private.has_permission('events.tickets.redeem') then raise exception 'Not authorised to redeem event tickets'; end if;
 select et.* into t from public.club_event_tickets et join public.voucher_issuances v on v.id=et.voucher_id where v.token_hash=encode(digest(trim(redemption_code),'sha256'),'hex') for update of et;
 if not found then raise exception 'Ticket not found'; end if;
 if t.status='redeemed' then perform app_private.write_audit_log('event.ticket_duplicate_redemption','club_event_ticket',t.id,null,null,null); return query select t.id,'already_redeemed',e.title,tt.name,t.redeemed_at from public.club_events e join public.club_event_ticket_types tt on tt.id=t.ticket_type_id where e.id=t.event_id; return; end if;
 if t.status<>'valid' then raise exception 'Ticket is not valid'; end if;
 update public.club_event_tickets set status='redeemed',redeemed_at=now(),redeemed_by=auth.uid() where id=t.id returning club_event_tickets.redeemed_at into t.redeemed_at;
 update public.voucher_issuances set status='claimed',claimed_at=now(),redemption_count=1 where id=t.voucher_id;
 perform app_private.write_audit_log('event.ticket_redeemed','club_event_ticket',t.id,null,jsonb_build_object('redeemed_at',t.redeemed_at),null);
 return query select t.id,'redeemed',e.title,tt.name,t.redeemed_at from public.club_events e join public.club_event_ticket_types tt on tt.id=t.ticket_type_id where e.id=t.event_id;
end $$;
revoke all on function public.redeem_event_ticket(text) from public;
grant execute on function public.redeem_event_ticket(text) to authenticated;
