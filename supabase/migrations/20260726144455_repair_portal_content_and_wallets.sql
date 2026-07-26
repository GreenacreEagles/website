create or replace function app_private.provision_profile_wallet()
returns trigger
language plpgsql
security definer
set search_path = public, app_private
as $$
begin
  insert into public.wallet_accounts(owner_id, account_type, status)
  values(new.id, 'user', 'active')
  on conflict do nothing;
  return new;
end
$$;

drop trigger if exists profiles_provision_wallet on public.profiles;
create trigger profiles_provision_wallet
after insert on public.profiles
for each row execute function app_private.provision_profile_wallet();

insert into public.wallet_accounts(owner_id, account_type, status)
select p.id, 'user', 'active'
from public.profiles p
where not exists (
  select 1 from public.wallet_accounts w
  where w.owner_id = p.id and w.account_type = 'user'
)
on conflict do nothing;

drop policy if exists announcements_public_active on public.club_announcements;
create policy announcements_public_active
on public.club_announcements for select
to anon, authenticated
using (status = 'active');

drop policy if exists coaching_public_read on public.coaching_resources;
drop policy if exists coaching_staff_read on public.coaching_resources;
drop policy if exists coaching_resources_active_read on public.coaching_resources;

create policy coaching_public_read
on public.coaching_resources for select
to anon
using (status = 'active' and visibility = 'public');

create policy coaching_resources_active_read
on public.coaching_resources for select
to authenticated
using (
  status = 'active'
  and (
    visibility = 'public'
    or app_private.has_permission('coaching_resources.read')
    or app_private.has_permission('coaching_resources.manage')
  )
);
