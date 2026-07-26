begin;

insert into public.seasons (id, name, year, starts_on, ends_on, status) values
('00000000-0000-4000-8000-000000000301', 'Public Teams Smoke Season', 2028, '2028-01-01', '2028-12-31', 'active');

insert into public.teams (id, season_id, name, slug, status, public) values
('00000000-0000-4000-8000-000000000302', '00000000-0000-4000-8000-000000000301', 'Public Active Team', 'public-active-team', 'active', true),
('00000000-0000-4000-8000-000000000303', '00000000-0000-4000-8000-000000000301', 'Private Active Team', 'private-active-team', 'active', false),
('00000000-0000-4000-8000-000000000304', '00000000-0000-4000-8000-000000000301', 'Public Inactive Team', 'public-inactive-team', 'inactive', true);

set local role anon;

do $$
begin
  if (select count(*) from public.teams where season_id = '00000000-0000-4000-8000-000000000301') <> 1 then
    raise exception 'anon must see exactly one active public team';
  end if;
  if exists (select 1 from public.teams where slug in ('private-active-team', 'public-inactive-team')) then
    raise exception 'private or inactive team leaked through team RLS';
  end if;
  if has_table_privilege('anon', 'public.player_records', 'select') then
    raise exception 'anon must not have broad player_records select access';
  end if;
end
$$;

reset role;
rollback;
