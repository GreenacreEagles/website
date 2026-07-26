insert into public.permissions(key, name, description)
values ('sponsors.view', 'View sponsors', 'View sponsor records in the administration portal.')
on conflict (key) do update set name = excluded.name, description = excluded.description;

alter table public.sponsors
  add column if not exists logo_object_key text,
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists updated_by uuid references public.profiles(id) on delete set null;

alter table public.sponsors
  drop constraint if exists sponsors_website_https_check;

alter table public.sponsors
  add constraint sponsors_website_https_check
  check (website_url is null or website_url ~ '^https://[^[:space:]]+$');

alter table public.sponsors enable row level security;

drop policy if exists sponsors_public_active on public.sponsors;
drop policy if exists sponsors_admin_read on public.sponsors;
drop policy if exists sponsors_manage on public.sponsors;

create policy sponsors_authenticated_active
on public.sponsors for select
to authenticated
using (
  status = 'active'
  or app_private.has_permission('sponsors.view')
  or app_private.has_permission('sponsors.manage')
);

create policy sponsors_manage
on public.sponsors for all
to authenticated
using (app_private.has_permission('sponsors.manage'))
with check (app_private.has_permission('sponsors.manage'));

revoke all on public.sponsors from anon;
grant select on public.sponsors to authenticated;
grant insert, update, delete on public.sponsors to authenticated;
grant all on public.sponsors to service_role;
