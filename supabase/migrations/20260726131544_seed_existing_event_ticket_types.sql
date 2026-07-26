insert into public.club_event_ticket_types(event_id,name,description,price_cents,currency,capacity,max_per_order,sort_order)
select id,'General admission','Entry to '||title,price_cents,'AUD',capacity,least(coalesce(per_user_ticket_limit,10),10),100
from public.club_events e
where not exists(select 1 from public.club_event_ticket_types t where t.event_id=e.id);
