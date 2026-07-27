-- Keep team records focused on season, competition and core team details.
-- Age groups and team-level venue fields are no longer part of the team model.

alter table public.teams
  drop column if exists age_group_id,
  drop column if exists home_venue,
  drop column if exists training_venue;

drop table if exists public.age_groups;
