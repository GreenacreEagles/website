do $$
declare definition text;
begin
  select pg_get_functiondef('public.create_event_ticket_order(uuid,int,text,text)'::regprocedure) into definition;
  definition := replace(definition,
    'on conflict(order_id,ticket_type_id) do nothing',
    'on conflict on constraint club_event_order_items_order_id_ticket_type_id_key do nothing');
  execute definition;
end $$;
