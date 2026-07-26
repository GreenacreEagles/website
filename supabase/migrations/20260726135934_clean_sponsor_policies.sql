drop policy if exists sponsors_manage_insert on public.sponsors;
drop policy if exists sponsors_manage_update on public.sponsors;
drop policy if exists sponsors_manage_delete on public.sponsors;

drop policy if exists sponsors_manage on public.sponsors;
create policy sponsors_manage_insert
on public.sponsors for insert to authenticated
with check (app_private.has_permission('sponsors.manage'));
create policy sponsors_manage_update
on public.sponsors for update to authenticated
using (app_private.has_permission('sponsors.manage'))
with check (app_private.has_permission('sponsors.manage'));
create policy sponsors_manage_delete
on public.sponsors for delete to authenticated
using (app_private.has_permission('sponsors.manage'));

create index if not exists sponsors_created_by_idx on public.sponsors(created_by);
create index if not exists sponsors_updated_by_idx on public.sponsors(updated_by);
