-- Public team presentation metadata and consent-gated, administrator-managed media.
alter table public.teams
  add column if not exists public boolean not null default false,
  add column if not exists slug text,
  add column if not exists summary text,
  add column if not exists image_object_key text,
  add column if not exists sort_order integer not null default 100;

update public.teams
set slug = trim(both '-' from regexp_replace(lower(name), '[^a-z0-9]+', '-', 'g'))
where slug is null;

alter table public.teams
  alter column slug set not null,
  add constraint teams_slug_format_check check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$');

create unique index if not exists teams_slug_unique_idx on public.teams (slug);
create index if not exists teams_active_count_idx on public.teams (status) where status = 'active';
create index if not exists teams_public_listing_idx
  on public.teams (season_id, sort_order, name)
  where public and status = 'active';

drop policy if exists public_read_teams on public.teams;
create policy public_read_public_teams
  on public.teams for select to anon
  using (status = 'active' and public);
create policy authenticated_read_active_teams
  on public.teams for select to authenticated
  using (status = 'active');

alter table public.player_records
  add column if not exists photo_object_key text,
  add column if not exists photo_updated_at timestamptz;

update public.player_records set photo_consent = false where photo_consent is null;
alter table public.player_records
  alter column photo_consent set default false,
  alter column photo_consent set not null;

alter table public.profiles
  add column if not exists public_photo_object_key text,
  add column if not exists public_photo_consent boolean not null default false,
  add column if not exists public_photo_updated_at timestamptz;

comment on column public.teams.public is 'Whether an active team may be presented on the public website.';
comment on column public.teams.image_object_key is 'Cloudflare R2 object key; never a complete delivery URL.';
comment on column public.player_records.photo_object_key is 'Administrator-managed Cloudflare R2 object key.';
comment on column public.player_records.photo_consent is 'Administrator-controlled consent for public squad photo display.';
comment on column public.profiles.public_photo_object_key is 'Administrator-managed Cloudflare R2 object key for public staff presentation.';

-- Public visitors do not receive direct access to player or profile rows.
revoke select on public.player_records from anon;
revoke select on public.team_players from anon;
revoke select on public.team_staff from anon;
revoke select on public.profiles from anon;
