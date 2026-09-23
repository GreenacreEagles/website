-- Public gallery albums. Club staff with content.manage upload a heading and photos.
-- The lowest sort_order photo is the cover shown on the gallery page.

create table public.gallery_albums (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  published boolean not null default true,
  sort_order integer not null default 100 check (sort_order between 0 and 10000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null
);

create table public.gallery_photos (
  id uuid primary key default gen_random_uuid(),
  album_id uuid not null references public.gallery_albums(id) on delete cascade,
  object_key text not null check (char_length(object_key) between 1 and 900),
  alt_text text check (alt_text is null or char_length(alt_text) <= 240),
  sort_order integer not null default 0 check (sort_order between 0 and 10000),
  created_at timestamptz not null default now()
);

create trigger gallery_albums_set_updated_at
before update on public.gallery_albums
for each row execute function app_private.set_updated_at();

create or replace function app_private.audit_gallery_change()
returns trigger
language plpgsql
security definer
set search_path = public, app_private
as $$
begin
  perform app_private.write_audit_log(
    tg_table_name || '.' || lower(tg_op),
    tg_table_name,
    coalesce(new.id, old.id),
    case when tg_op = 'INSERT' then null else to_jsonb(old) end,
    case when tg_op = 'DELETE' then null else to_jsonb(new) end,
    null
  );
  return coalesce(new, old);
end;
$$;

create trigger gallery_albums_audit
after insert or update or delete on public.gallery_albums
for each row execute function app_private.audit_gallery_change();

create trigger gallery_photos_audit
after insert or update or delete on public.gallery_photos
for each row execute function app_private.audit_gallery_change();

create index gallery_albums_public_idx
on public.gallery_albums (created_at desc)
where published;

create index gallery_photos_album_idx
on public.gallery_photos (album_id, sort_order, created_at);

alter table public.gallery_albums enable row level security;
alter table public.gallery_photos enable row level security;

create policy gallery_albums_public_read
on public.gallery_albums
for select
to anon
using (published);

create policy gallery_albums_member_read
on public.gallery_albums
for select
to authenticated
using (published or app_private.has_permission('content.manage'));

create policy gallery_albums_manage
on public.gallery_albums
for all
to authenticated
using (app_private.has_permission('content.manage'))
with check (app_private.has_permission('content.manage'));

create policy gallery_photos_public_read
on public.gallery_photos
for select
to anon
using (
  exists (
    select 1
    from public.gallery_albums album
    where album.id = gallery_photos.album_id
      and album.published
  )
);

create policy gallery_photos_member_read
on public.gallery_photos
for select
to authenticated
using (
  app_private.has_permission('content.manage')
  or exists (
    select 1
    from public.gallery_albums album
    where album.id = gallery_photos.album_id
      and album.published
  )
);

create policy gallery_photos_manage
on public.gallery_photos
for all
to authenticated
using (app_private.has_permission('content.manage'))
with check (app_private.has_permission('content.manage'));

grant select on public.gallery_albums, public.gallery_photos to anon, authenticated;
grant insert, update, delete on public.gallery_albums, public.gallery_photos to authenticated;
grant select, insert, update, delete on public.gallery_albums, public.gallery_photos to service_role;
