-- Anonymous visitors use the public key, and they cannot execute
-- app_private.has_permission. Keep the public read rule to published albums only.
-- Signed-in staff still see hidden albums through the member and manage rules.

drop policy if exists gallery_albums_public_read on public.gallery_albums;
drop policy if exists gallery_albums_member_read on public.gallery_albums;
drop policy if exists gallery_photos_public_read on public.gallery_photos;
drop policy if exists gallery_photos_member_read on public.gallery_photos;

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
