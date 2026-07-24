-- Coaching resource library metadata, search indexes and explicit API grants.

alter table public.coaching_resources
add column if not exists slug text,
add column if not exists external_url text,
add column if not exists attachment_file_id uuid references public.file_records(id) on delete set null,
add column if not exists published_at timestamptz,
add column if not exists review_due_on date;

create unique index if not exists coaching_resources_slug_unique
on public.coaching_resources (slug)
where slug is not null;

create index if not exists coaching_resources_status_visibility_idx
on public.coaching_resources (status, visibility, updated_at desc);

create index if not exists coaching_resources_resource_type_idx
on public.coaching_resources (resource_type, updated_at desc);

create index if not exists coaching_resources_age_group_gin_idx
on public.coaching_resources using gin (age_group_tags);

create index if not exists coaching_resources_skill_level_gin_idx
on public.coaching_resources using gin (skill_level_tags);

create or replace function app_private.slugify(value text)
returns text
language sql
immutable
set search_path = public, extensions
as $$
  select nullif(trim(both '-' from regexp_replace(lower(coalesce(value, '')), '[^a-z0-9]+', '-', 'g')), '');
$$;

create or replace function app_private.coaching_resource_before_write()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  new.slug := coalesce(nullif(trim(new.slug), ''), app_private.slugify(new.title));

  if new.status = 'published' and new.published_at is null then
    new.published_at := now();
  elsif new.status <> 'published' then
    new.published_at := null;
  end if;

  return new;
end;
$$;

drop trigger if exists coaching_resource_before_write on public.coaching_resources;
create trigger coaching_resource_before_write
before insert or update on public.coaching_resources
for each row execute function app_private.coaching_resource_before_write();

grant select on public.coaching_resources to anon, authenticated;
grant insert, update, delete on public.coaching_resources to authenticated;

grant select on public.file_records to anon, authenticated;
