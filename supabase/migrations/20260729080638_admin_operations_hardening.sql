-- Focused forward-only hardening for admin operations.

alter table public.coaching_resources add column if not exists sort_order integer not null default 100;
do $$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.coaching_resources'::regclass and conname='coaching_resources_sort_order_check') then
  alter table public.coaching_resources add constraint coaching_resources_sort_order_check check(sort_order between 0 and 10000) not valid;
  alter table public.coaching_resources validate constraint coaching_resources_sort_order_check;
 end if;
end $$;
create index if not exists coaching_resources_sort_order_idx on public.coaching_resources(sort_order,id);

alter table public.order_status_history add column if not exists status_type text not null default 'fulfilment';
do $$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.order_status_history'::regclass and conname='order_status_history_status_type_check') then
  alter table public.order_status_history add constraint order_status_history_status_type_check check(status_type in ('payment','fulfilment')) not valid;
  alter table public.order_status_history validate constraint order_status_history_status_type_check;
 end if;
end $$;
create index if not exists order_status_history_order_created_idx on public.order_status_history(order_id,created_at desc);

alter table public.wallet_accounts
 add column if not exists blocked_at timestamptz,
 add column if not exists blocked_by uuid references public.profiles(id) on delete set null,
 add column if not exists block_reason text;
do $$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.wallet_accounts'::regclass and conname='wallet_accounts_block_reason_length') then
  alter table public.wallet_accounts add constraint wallet_accounts_block_reason_length check(block_reason is null or char_length(block_reason)<=500) not valid;
  alter table public.wallet_accounts validate constraint wallet_accounts_block_reason_length;
 end if;
end $$;

create or replace function public.generate_admin_slug(target_kind text,target_title text,current_id uuid default null)
returns text language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); base text; candidate text; suffix integer:=1; conflict_found boolean; target_table text; required_permission text;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 case target_kind
  when 'news' then target_table:='content_articles'; required_permission:='content.manage';
  when 'coaching_resource' then target_table:='coaching_resources'; required_permission:='coaching_resources.manage';
  else raise exception 'Unsupported slug target';
 end case;
 if not app_private.has_permission(required_permission) then raise exception 'Not authorised'; end if;
 base:=app_private.slugify(target_title);
 if base is null then base:='item'; end if;
 base:=left(base,130);
 candidate:=base;
 loop
  execute format('select exists(select 1 from public.%I where slug=$1 and ($2 is null or id<>$2))',target_table)
   into conflict_found using candidate,current_id;
  exit when not conflict_found;
  suffix:=suffix+1; candidate:=left(base,130-length(suffix::text)-1)||'-'||suffix;
 end loop;
 return candidate;
end $$;
revoke all on function public.generate_admin_slug(text,text,uuid) from public,anon;
grant execute on function public.generate_admin_slug(text,text,uuid) to authenticated,service_role;

create or replace function public.reorder_admin_items(target_kind text,target_ids uuid[])
returns integer language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); required_permission text; changed integer:=0; supplied integer; distinct_count integer;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 supplied:=coalesce(array_length(target_ids,1),0);
 select count(distinct value) into distinct_count from unnest(coalesce(target_ids,'{}'::uuid[])) value;
 if supplied=0 or supplied<>distinct_count or supplied>500 then raise exception 'Invalid reorder list'; end if;
 case target_kind
  when 'canteen_categories' then required_permission:='canteen.manage';
  when 'social_posts' then required_permission:='social_posts.manage';
  when 'coaching_resources' then required_permission:='coaching_resources.manage';
  else raise exception 'Unsupported reorder target';
 end case;
 if not app_private.has_permission(required_permission) then raise exception 'Not authorised'; end if;
 if target_kind='canteen_categories' then
  with desired as (select value id,ordinality::int*10 position from unnest(target_ids) with ordinality), updated as (
   update public.canteen_categories t set display_order=d.position,updated_at=now() from desired d where t.id=d.id and t.display_order<>d.position returning 1)
  select count(*) into changed from updated;
 elsif target_kind='social_posts' then
  with desired as (select value id,ordinality::int*10 position from unnest(target_ids) with ordinality), updated as (
   update public.social_posts t set sort_order=d.position,updated_at=now(),updated_by=actor from desired d where t.id=d.id and t.sort_order<>d.position returning 1)
  select count(*) into changed from updated;
 else
  with desired as (select value id,ordinality::int*10 position from unnest(target_ids) with ordinality), updated as (
   update public.coaching_resources t set sort_order=d.position,updated_at=now() from desired d where t.id=d.id and t.sort_order<>d.position returning 1)
  select count(*) into changed from updated;
 end if;
 perform app_private.write_audit_log(target_kind||'.reordered',target_kind,null,null,jsonb_build_object('ids',target_ids,'changed',changed),'Admin reorder');
 return changed;
end $$;
revoke all on function public.reorder_admin_items(text,uuid[]) from public,anon;
grant execute on function public.reorder_admin_items(text,uuid[]) to authenticated,service_role;

create or replace function public.set_wallet_status(target_wallet_id uuid,target_status text,target_reason text default null)
returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); before_row public.wallet_accounts%rowtype;
begin
 if actor is null or not app_private.has_permission('wallet.adjust') then raise exception 'Not authorised'; end if;
 if target_status not in ('active','frozen') then raise exception 'Invalid wallet status'; end if;
 if target_reason is not null and char_length(trim(target_reason))>500 then raise exception 'Reason is too long'; end if;
 select * into before_row from public.wallet_accounts where id=target_wallet_id for update;
 if not found then raise exception 'Wallet not found'; end if;
 if before_row.status=target_status then return; end if;
 if before_row.status='closed' then raise exception 'Closed wallets cannot be reopened'; end if;
 update public.wallet_accounts set status=target_status,blocked_at=case when target_status='frozen' then now() else null end,blocked_by=case when target_status='frozen' then actor else null end,block_reason=case when target_status='frozen' then nullif(trim(target_reason),'') else null end,updated_at=now() where id=target_wallet_id;
 perform app_private.write_audit_log('wallet.'||case when target_status='frozen' then 'blocked' else 'unblocked' end,'wallet_account',target_wallet_id,to_jsonb(before_row),jsonb_build_object('status',target_status,'actor',actor,'reason',nullif(trim(target_reason),'')),target_reason);
end $$;
revoke all on function public.set_wallet_status(uuid,text,text) from public,anon;
grant execute on function public.set_wallet_status(uuid,text,text) to authenticated,service_role;

create or replace function public.admin_user_directory(search_text text default null,page_limit integer default 50,page_offset integer default 0,target_user_id uuid default null)
returns table(id uuid,full_name text,preferred_name text,email text,mobile text,account_status text,onboarding_completed_at timestamptz,created_at timestamptz,child_account boolean,child_username text,total_count bigint)
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); term text:=nullif(trim(search_text),'');
begin
 if actor is null or not app_private.has_permission('users.read') then raise exception 'Not authorised'; end if;
 if page_limit not between 1 and 100 or page_offset<0 then raise exception 'Invalid pagination'; end if;
 return query
 select p.id,p.full_name,p.preferred_name,case when child.child_user_id is not null then null else u.email::text end,p.mobile,p.account_status,p.onboarding_completed_at,p.created_at,
  child.child_user_id is not null,child.username,count(*) over()
 from public.profiles p join auth.users u on u.id=p.id left join public.managed_child_accounts child on child.child_user_id=p.id
 where (target_user_id is null or p.id=target_user_id) and (term is null or concat_ws(' ',p.full_name,p.preferred_name,u.email,child.username,p.mobile) ilike '%'||replace(replace(term,'%','\%'),'_','\_')||'%' escape '\')
 order by coalesce(nullif(p.preferred_name,''),nullif(p.full_name,''),u.email,child.username),p.id
 limit page_limit offset page_offset;
end $$;
revoke all on function public.admin_user_directory(text,integer,integer,uuid) from public,anon;
grant execute on function public.admin_user_directory(text,integer,integer,uuid) to authenticated,service_role;

create or replace function app_private.update_canteen_order_state(target_order_id uuid,target_order_status text default null,target_payment_status text default null,change_reason text default null)
returns table(order_id uuid,order_number text,old_order_status text,new_order_status text,old_payment_status text,new_payment_status text,customer_id uuid,recipient_id uuid,issued_vouchers integer)
language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); order_row public.canteen_orders%rowtype; next_order text; next_payment text; issued_count integer:=0; can_manage boolean; can_fulfil boolean;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 can_manage:=app_private.has_permission('canteen.orders.manage');
 can_fulfil:=can_manage or app_private.has_permission('canteen.orders.fulfil');
 if not can_fulfil then raise exception 'Worker not authorised'; end if;
 if target_payment_status is not null and not can_manage then raise exception 'Not authorised to change payment'; end if;
 select * into order_row from public.canteen_orders where id=target_order_id for update;
 if not found then raise exception 'Order not found'; end if;
 next_payment:=coalesce(target_payment_status,order_row.payment_status);
 next_order:=coalesce(target_order_status,order_row.order_status);
 if next_payment not in ('unpaid','awaiting_payment','paid','partially_refunded','refunded') then raise exception 'Invalid payment status'; end if;
 if next_order not in ('accepted','preparing','ready_for_pickup','collected','cancelled') then raise exception 'Invalid fulfilment status'; end if;
 if next_order='cancelled' and not can_manage then raise exception 'Not authorised to cancel orders'; end if;
 if target_payment_status='paid' and order_row.order_status in ('awaiting_payment','paid') and target_order_status is null then next_order:='accepted'; end if;
 if next_order='collected' and next_payment<>'paid' then raise exception 'Payment must be confirmed before collection'; end if;
 if order_row.order_status in ('collected','cancelled','refunded','expired') and next_order<>order_row.order_status then raise exception 'Closed orders cannot be moved'; end if;
 if next_order<>order_row.order_status then
  if order_row.order_status in ('awaiting_payment','paid') and next_order not in ('accepted','cancelled') then raise exception 'Invalid fulfilment transition'; end if;
  if order_row.order_status='accepted' and next_order not in ('preparing','ready_for_pickup','collected','cancelled') then raise exception 'Invalid fulfilment transition'; end if;
  if order_row.order_status='preparing' and next_order not in ('ready_for_pickup','collected','cancelled') then raise exception 'Invalid fulfilment transition'; end if;
  if order_row.order_status='ready_for_pickup' and next_order not in ('collected','cancelled') then raise exception 'Invalid fulfilment transition'; end if;
 end if;
 update public.canteen_orders set order_status=next_order,payment_status=next_payment,pickup_code=coalesce(pickup_code,'GEORDER:'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12))),completed_at=case when next_order='collected' then coalesce(completed_at,now()) else completed_at end,completed_by=case when next_order='collected' then coalesce(completed_by,actor) else completed_by end,completion_source=case when next_order='collected' then coalesce(completion_source,'admin') else completion_source end,updated_at=case when next_order<>order_row.order_status or next_payment<>order_row.payment_status then now() else updated_at end where id=target_order_id;
 if next_payment<>order_row.payment_status then insert into public.order_status_history(order_id,old_status,new_status,changed_by,reason,status_type) values(target_order_id,order_row.payment_status,next_payment,actor,change_reason,'payment'); end if;
 if next_order<>order_row.order_status then insert into public.order_status_history(order_id,old_status,new_status,changed_by,reason,status_type) values(target_order_id,order_row.order_status,next_order,actor,change_reason,'fulfilment'); end if;
 if next_payment='paid' and order_row.payment_status<>'paid' then issued_count:=app_private.issue_canteen_order_vouchers(target_order_id); end if;
 if next_order<>order_row.order_status or next_payment<>order_row.payment_status then perform app_private.write_audit_log('canteen.order_state_changed','canteen_order',target_order_id,jsonb_build_object('payment_status',order_row.payment_status,'order_status',order_row.order_status),jsonb_build_object('payment_status',next_payment,'order_status',next_order,'actor',actor),change_reason); end if;
 return query select target_order_id,order_row.order_number,order_row.order_status,next_order,order_row.payment_status,next_payment,order_row.customer_id,order_row.recipient_id,issued_count;
end $$;
revoke all on function app_private.update_canteen_order_state(uuid,text,text,text) from public,anon,authenticated;
grant execute on function app_private.update_canteen_order_state(uuid,text,text,text) to authenticated,service_role;
revoke all on function public.update_canteen_order_state(uuid,text,text,text) from public,anon;
grant execute on function public.update_canteen_order_state(uuid,text,text,text) to authenticated,service_role;
