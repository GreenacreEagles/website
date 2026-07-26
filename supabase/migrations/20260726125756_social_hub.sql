insert into public.permissions (key, name, description) values
('social_profiles.view', 'View social profiles', 'View configured official social profiles'),
('social_profiles.manage', 'Manage social profiles', 'Create, edit, reorder and remove official social profiles'),
('social_posts.view', 'View social posts', 'View selected social posts'),
('social_posts.manage', 'Manage social posts', 'Create, edit, feature, reorder and remove selected social posts')
on conflict (key) do update set name = excluded.name, description = excluded.description;

create table public.social_profiles (
  id uuid primary key default gen_random_uuid(),
  platform text not null check (platform in ('instagram','facebook','tiktok')),
  display_name text not null check (char_length(display_name) between 2 and 120),
  username text,
  profile_url text not null check (profile_url ~ '^https://'),
  active boolean not null default true,
  sort_order integer not null default 100 check (sort_order between 0 and 10000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  unique (platform)
);

create table public.social_posts (
  id uuid primary key default gen_random_uuid(),
  platform text not null check (platform in ('instagram','facebook','tiktok')),
  post_url text not null unique check (post_url ~ '^https://'),
  title text check (char_length(title) <= 180),
  caption text check (char_length(caption) <= 2000),
  image_object_key text,
  image_alt_text text check (char_length(image_alt_text) <= 240),
  published_at timestamptz,
  active boolean not null default true,
  featured boolean not null default false,
  sort_order integer not null default 100 check (sort_order between 0 and 10000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null
);

create trigger social_profiles_set_updated_at before update on public.social_profiles
for each row execute function app_private.set_updated_at();
create trigger social_posts_set_updated_at before update on public.social_posts
for each row execute function app_private.set_updated_at();

create or replace function app_private.audit_social_change() returns trigger
language plpgsql security definer set search_path = public, app_private as $$
declare action_name text;
begin
  action_name := tg_table_name || '.' || lower(tg_op);
  if tg_op = 'UPDATE' then
    if old.active is distinct from new.active then action_name := tg_table_name || case when new.active then '.activated' else '.deactivated' end;
    elsif tg_table_name = 'social_posts' and old.featured is distinct from new.featured then action_name := tg_table_name || case when new.featured then '.featured' else '.unfeatured' end;
    elsif tg_table_name = 'social_posts' and old.image_object_key is distinct from new.image_object_key then action_name := tg_table_name || '.image_changed';
    end if;
  end if;
  perform app_private.write_audit_log(
    action_name, tg_table_name, coalesce(new.id, old.id),
    case when tg_op = 'INSERT' then null else to_jsonb(old) end,
    case when tg_op = 'DELETE' then null else to_jsonb(new) end, null
  );
  return coalesce(new, old);
end $$;

create trigger social_profiles_audit after insert or update or delete on public.social_profiles
for each row execute function app_private.audit_social_change();
create trigger social_posts_audit after insert or update or delete on public.social_posts
for each row execute function app_private.audit_social_change();

create index social_profiles_public_idx on public.social_profiles (sort_order, platform) where active;
create index social_posts_public_idx on public.social_posts (featured desc, sort_order, published_at desc, created_at desc) where active;

alter table public.social_profiles enable row level security;
alter table public.social_posts enable row level security;

create policy social_profiles_public_read on public.social_profiles for select to anon using (active);
create policy social_profiles_authorised_read on public.social_profiles for select to authenticated
using (active or app_private.has_permission('social_profiles.view') or app_private.has_permission('social_profiles.manage'));
create policy social_profiles_authorised_manage on public.social_profiles for all to authenticated
using (app_private.has_permission('social_profiles.manage'))
with check (app_private.has_permission('social_profiles.manage'));

create policy social_posts_public_read on public.social_posts for select to anon using (active);
create policy social_posts_authorised_read on public.social_posts for select to authenticated
using (active or app_private.has_permission('social_posts.view') or app_private.has_permission('social_posts.manage'));
create policy social_posts_authorised_manage on public.social_posts for all to authenticated
using (app_private.has_permission('social_posts.manage'))
with check (app_private.has_permission('social_posts.manage'));

grant select on public.social_profiles, public.social_posts to anon;
grant select, insert, update, delete on public.social_profiles, public.social_posts to authenticated;
grant select, insert, update, delete on public.social_profiles, public.social_posts to service_role;

insert into public.social_profiles (platform, display_name, username, profile_url, sort_order) values
('instagram', 'Greenacre Eagles FC', '@greenacreeagles', 'https://www.instagram.com/greenacreeagles', 10),
('facebook', 'Greenacre Eagles FC', '@eaglesgreenacreFC', 'https://www.facebook.com/eaglesgreenacreFC', 20),
('tiktok', 'Greenacre Eagles FC', null, 'https://www.tiktok.com/discover/greenacre-eagles-fc', 30)
on conflict (platform) do update set display_name=excluded.display_name, username=excluded.username, profile_url=excluded.profile_url, sort_order=excluded.sort_order, active=true;
