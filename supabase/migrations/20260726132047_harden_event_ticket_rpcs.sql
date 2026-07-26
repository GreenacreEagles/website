revoke execute on function public.create_event_ticket_order(uuid,int,text,text) from anon;
revoke execute on function public.redeem_event_ticket(text) from anon;
grant execute on function public.create_event_ticket_order(uuid,int,text,text) to authenticated;
grant execute on function public.redeem_event_ticket(text) to authenticated;
