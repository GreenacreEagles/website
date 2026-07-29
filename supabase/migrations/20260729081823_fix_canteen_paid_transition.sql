-- Normalise legacy pre-acceptance order states before fulfilment validation.

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
 if target_payment_status='paid' and order_row.order_status in ('awaiting_payment','paid') and target_order_status is null then next_order:='accepted'; end if;
 if next_payment not in ('unpaid','awaiting_payment','paid','partially_refunded','refunded') then raise exception 'Invalid payment status'; end if;
 if next_order not in ('accepted','preparing','ready_for_pickup','collected','cancelled') then raise exception 'Invalid fulfilment status'; end if;
 if next_order='cancelled' and not can_manage then raise exception 'Not authorised to cancel orders'; end if;
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
