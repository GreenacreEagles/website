begin;

do $$
begin
  if to_regclass('public.age_groups') is not null then raise exception 'Age groups table still exists'; end if;
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='teams' and column_name in('age_group_id','home_venue','training_venue')) then raise exception 'Removed team fields still exist'; end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='teams' and column_name='season_id') then raise exception 'Season relation was removed'; end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='teams' and column_name='competition_id') then raise exception 'Competition relation was removed'; end if;
end;
$$;

rollback;
