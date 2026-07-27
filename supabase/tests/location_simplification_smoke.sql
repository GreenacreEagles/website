begin;

do $$
begin
  if to_regclass('public.venues') is not null then raise exception 'Shared venues table still exists'; end if;
  if to_regclass('public.canteen_venues') is not null then raise exception 'Canteen venues table still exists'; end if;
  if exists(select 1 from information_schema.columns where table_schema='public' and column_name in('venue_id','home_venue_id','training_venue_id') and table_name in('teams','club_events','fixtures','training_sessions','volunteer_shifts','canteen_orders','voucher_issuances','voucher_redemptions')) then raise exception 'Venue foreign-key columns remain'; end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='club_events' and column_name='venue' and data_type='text') then raise exception 'Events do not have a typed venue field'; end if;
end;
$$;

rollback;
