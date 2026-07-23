-- Family relationship invitations, guardian-safe family views and voucher assignment controls.

insert into public.permissions (key, name, description)
values
  ('families.invite', 'Invite family guardians', 'Invite another guardian into an existing family relationship.')
on conflict (key) do update
set name = excluded.name,
    description = excluded.description;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.key = 'families.invite'
where r.key in ('super_administrator', 'club_administrator', 'registrar', 'parent_guardian')
on conflict do nothing;

create table if not exists public.family_relationship_invitations (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  invited_email text not null check (invited_email = lower(trim(invited_email)) and invited_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  invited_user_id uuid references public.profiles(id) on delete set null,
  relationship text not null default 'guardian' check (relationship in ('parent','guardian','carer')),
  invited_by uuid not null references public.profiles(id) on delete restrict,
  status text not null default 'pending' check (status in ('pending','accepted','cancelled','expired')),
  message text,
  expires_at timestamptz not null default now() + interval '30 days',
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (family_id, invited_email, status)
);

create table if not exists public.family_voucher_assignments (
  id uuid primary key default gen_random_uuid(),
  voucher_id uuid not null references public.voucher_issuances(id) on delete restrict,
  from_user_id uuid references public.profiles(id) on delete set null,
  to_user_id uuid not null references public.profiles(id) on delete restrict,
  family_id uuid not null references public.families(id) on delete restrict,
  assigned_by uuid not null references public.profiles(id) on delete restrict,
  note text,
  created_at timestamptz not null default now()
);

alter table public.voucher_issuances
add column if not exists assigned_by uuid references public.profiles(id) on delete set null,
add column if not exists assigned_at timestamptz,
add column if not exists assignment_note text;

create index if not exists family_invitations_family_status_idx on public.family_relationship_invitations (family_id, status, created_at desc);
create index if not exists family_invitations_invited_user_idx on public.family_relationship_invitations (invited_user_id, status);
create index if not exists family_invitations_email_idx on public.family_relationship_invitations (invited_email, status);
create index if not exists family_voucher_assignments_family_idx on public.family_voucher_assignments (family_id, created_at desc);
create index if not exists voucher_issuances_family_beneficiary_idx on public.voucher_issuances (family_id, beneficiary_id, status);

alter table public.family_relationship_invitations enable row level security;
alter table public.family_voucher_assignments enable row level security;

create or replace function app_private.can_manage_family(target_family_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select app_private.has_permission('families.manage')
  or exists (
    select 1
    from public.family_members fm
    where fm.family_id = target_family_id
      and fm.user_id = auth.uid()
      and fm.status = 'active'
      and (fm.can_manage or fm.is_primary_guardian)
  );
$$;

create or replace function app_private.is_active_family_member(target_family_id uuid, target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1
    from public.family_members fm
    where fm.family_id = target_family_id
      and fm.user_id = target_user_id
      and fm.status = 'active'
  );
$$;

create or replace function app_private.can_assign_family_wallet_item(target_family_id uuid, target_child_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select app_private.has_permission('families.manage')
  or exists (
    select 1
    from public.family_members guardian
    join public.family_members child on child.family_id = guardian.family_id
    where guardian.family_id = target_family_id
      and guardian.user_id = auth.uid()
      and guardian.status = 'active'
      and guardian.relationship in ('parent','guardian','carer')
      and (guardian.can_manage or guardian.can_spend or guardian.is_primary_guardian)
      and child.user_id = target_child_id
      and child.status = 'active'
      and child.relationship in ('child','player','dependent')
  );
$$;

revoke all on function app_private.can_manage_family(uuid) from public;
revoke all on function app_private.is_active_family_member(uuid, uuid) from public;
revoke all on function app_private.can_assign_family_wallet_item(uuid, uuid) from public;
grant execute on function app_private.can_manage_family(uuid) to authenticated;
grant execute on function app_private.is_active_family_member(uuid, uuid) to authenticated;
grant execute on function app_private.can_assign_family_wallet_item(uuid, uuid) to authenticated;

create policy family_invitations_related_read
on public.family_relationship_invitations
for select
to authenticated
using (
  invited_user_id = auth.uid()
  or lower(invited_email) = lower((select email from public.profiles where id = auth.uid()))
  or invited_by = auth.uid()
  or app_private.can_manage_family(family_id)
);

create policy family_invitations_manage_insert
on public.family_relationship_invitations
for insert
to authenticated
with check (
  invited_by = auth.uid()
  and app_private.can_manage_family(family_id)
);

create policy family_invitations_related_update
on public.family_relationship_invitations
for update
to authenticated
using (
  app_private.can_manage_family(family_id)
  or invited_user_id = auth.uid()
  or lower(invited_email) = lower((select email from public.profiles where id = auth.uid()))
)
with check (
  app_private.can_manage_family(family_id)
  or invited_user_id = auth.uid()
  or lower(invited_email) = lower((select email from public.profiles where id = auth.uid()))
);

create policy family_voucher_assignments_related_read
on public.family_voucher_assignments
for select
to authenticated
using (
  assigned_by = auth.uid()
  or from_user_id = auth.uid()
  or to_user_id = auth.uid()
  or app_private.can_manage_family(family_id)
);

drop policy if exists vouchers_owner_or_manager_read on public.voucher_issuances;
create policy vouchers_owner_family_or_manager_read
on public.voucher_issuances
for select
to authenticated
using (
  beneficiary_id = auth.uid()
  or app_private.has_permission('canteen.vouchers.manage')
  or (
    family_id is not null
    and exists (
      select 1
      from public.family_members fm
      where fm.family_id = voucher_issuances.family_id
        and fm.user_id = auth.uid()
        and fm.status = 'active'
    )
  )
);

drop policy if exists wallets_owner_or_admin_read on public.wallet_accounts;
create policy wallets_owner_family_or_admin_read
on public.wallet_accounts
for select
to authenticated
using (
  owner_id = auth.uid()
  or app_private.has_permission('wallet.read')
  or (
    family_id is not null
    and exists (
      select 1
      from public.family_members fm
      where fm.family_id = wallet_accounts.family_id
        and fm.user_id = auth.uid()
        and fm.status = 'active'
    )
  )
  or (
    owner_id is not null
    and exists (
      select 1
      from public.family_members child
      join public.family_members guardian on guardian.family_id = child.family_id
      where child.user_id = wallet_accounts.owner_id
        and child.status = 'active'
        and guardian.user_id = auth.uid()
        and guardian.status = 'active'
        and guardian.relationship in ('parent','guardian','carer')
    )
  )
);

drop policy if exists ledger_owner_or_admin_read on public.wallet_ledger_entries;
create policy ledger_owner_family_or_admin_read
on public.wallet_ledger_entries
for select
to authenticated
using (
  app_private.has_permission('wallet.read')
  or exists (
    select 1
    from public.wallet_accounts wa
    where wa.id = wallet_account_id
      and (
        wa.owner_id = auth.uid()
        or (
          wa.family_id is not null
          and exists (
            select 1
            from public.family_members fm
            where fm.family_id = wa.family_id
              and fm.user_id = auth.uid()
              and fm.status = 'active'
          )
        )
        or (
          wa.owner_id is not null
          and exists (
            select 1
            from public.family_members child
            join public.family_members guardian on guardian.family_id = child.family_id
            where child.user_id = wa.owner_id
              and child.status = 'active'
              and guardian.user_id = auth.uid()
              and guardian.status = 'active'
              and guardian.relationship in ('parent','guardian','carer')
          )
        )
      )
  )
);

create or replace function public.invite_family_guardian(
  target_family_id uuid,
  invite_email text,
  invite_relationship text default 'guardian',
  invite_message text default null
)
returns uuid
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  normalised_email text := lower(trim(invite_email));
  invited_profile_id uuid;
  invitation_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if invite_relationship not in ('parent','guardian','carer') then
    raise exception 'Invalid relationship';
  end if;

  if not app_private.can_manage_family(target_family_id) then
    raise exception 'You cannot invite guardians for this family';
  end if;

  select id into invited_profile_id
  from public.profiles
  where lower(email) = normalised_email
  limit 1;

  insert into public.family_relationship_invitations (
    family_id,
    invited_email,
    invited_user_id,
    relationship,
    invited_by,
    message
  )
  values (
    target_family_id,
    normalised_email,
    invited_profile_id,
    invite_relationship,
    auth.uid(),
    nullif(trim(invite_message), '')
  )
  on conflict (family_id, invited_email, status)
  do update set
    invited_user_id = excluded.invited_user_id,
    relationship = excluded.relationship,
    invited_by = excluded.invited_by,
    message = excluded.message,
    expires_at = now() + interval '30 days',
    updated_at = now()
  returning id into invitation_id;

  if invited_profile_id is not null then
    insert into public.notifications (recipient_id, title, body, related_entity_type, related_entity_id)
    values (invited_profile_id, 'Family guardian invitation', 'You have been invited to join a Greenacre Eagles family group.', 'family_invitation', invitation_id);
  end if;

  perform app_private.write_audit_log(
    'family.guardian_invited',
    'family',
    target_family_id,
    null,
    jsonb_build_object('invitation_id', invitation_id, 'email', normalised_email, 'relationship', invite_relationship),
    invite_message
  );

  return invitation_id;
end;
$$;

create or replace function app_private.accept_family_invitation(target_invitation_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  invitation public.family_relationship_invitations%rowtype;
  current_email text;
  member_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into invitation
  from public.family_relationship_invitations
  where id = target_invitation_id
  for update;

  if not found then
    raise exception 'Invitation not found';
  end if;

  select lower(email) into current_email from public.profiles where id = auth.uid();

  if invitation.status <> 'pending' or invitation.expires_at <= now() then
    raise exception 'Invitation is not active';
  end if;

  if invitation.invited_user_id is not null and invitation.invited_user_id <> auth.uid() then
    raise exception 'Invitation is for another user';
  end if;

  if lower(invitation.invited_email) <> current_email then
    raise exception 'Invitation email does not match your account';
  end if;

  insert into public.family_members (
    family_id,
    user_id,
    relationship,
    is_primary_guardian,
    can_manage,
    can_spend,
    status,
    invited_by,
    accepted_at
  )
  values (
    invitation.family_id,
    auth.uid(),
    invitation.relationship,
    false,
    false,
    false,
    'active',
    invitation.invited_by,
    now()
  )
  on conflict (family_id, user_id)
  do update set
    relationship = excluded.relationship,
    status = 'active',
    accepted_at = coalesce(public.family_members.accepted_at, now()),
    updated_at = now()
  returning id into member_id;

  update public.family_relationship_invitations
  set status = 'accepted',
      invited_user_id = auth.uid(),
      accepted_at = now(),
      updated_at = now()
  where id = target_invitation_id;

  perform app_private.write_audit_log(
    'family.guardian_invitation_accepted',
    'family_member',
    member_id,
    null,
    jsonb_build_object('family_id', invitation.family_id, 'user_id', auth.uid()),
    null
  );

  return member_id;
end;
$$;

create or replace function app_private.assign_voucher_to_family_member(
  target_voucher_id uuid,
  target_child_id uuid,
  assignment_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  voucher public.voucher_issuances%rowtype;
  target_family_id uuid;
  assignment_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into voucher
  from public.voucher_issuances
  where id = target_voucher_id
  for update;

  if not found then
    raise exception 'Voucher not found';
  end if;

  if voucher.status <> 'active' or voucher.remaining_value_cents <= 0 then
    raise exception 'Voucher is not assignable';
  end if;

  if voucher.redemption_count > 0 then
    raise exception 'Partially used vouchers cannot be reassigned';
  end if;

  select child.family_id
  into target_family_id
  from public.family_members child
  join public.family_members guardian on guardian.family_id = child.family_id
  where child.user_id = target_child_id
    and child.status = 'active'
    and child.relationship in ('child','player','dependent')
    and guardian.user_id = auth.uid()
    and guardian.status = 'active'
    and guardian.relationship in ('parent','guardian','carer')
    and (guardian.can_manage or guardian.can_spend or guardian.is_primary_guardian)
  limit 1;

  if target_family_id is null then
    raise exception 'You cannot assign vouchers to that person';
  end if;

  if voucher.beneficiary_id <> auth.uid()
    and not (
      voucher.family_id = target_family_id
      and app_private.can_assign_family_wallet_item(target_family_id, target_child_id)
    )
    and not app_private.has_permission('canteen.vouchers.manage')
  then
    raise exception 'You cannot assign this voucher';
  end if;

  update public.voucher_issuances
  set beneficiary_id = target_child_id,
      family_id = target_family_id,
      assigned_by = auth.uid(),
      assigned_at = now(),
      assignment_note = nullif(trim(assignment_note), ''),
      updated_at = now()
  where id = target_voucher_id;

  insert into public.family_voucher_assignments (
    voucher_id,
    from_user_id,
    to_user_id,
    family_id,
    assigned_by,
    note
  )
  values (
    target_voucher_id,
    voucher.beneficiary_id,
    target_child_id,
    target_family_id,
    auth.uid(),
    nullif(trim(assignment_note), '')
  )
  returning id into assignment_id;

  insert into public.notifications (recipient_id, title, body, related_entity_type, related_entity_id)
  values (target_child_id, 'Voucher assigned', 'A family voucher has been assigned to your wallet.', 'voucher', target_voucher_id);

  perform app_private.write_audit_log(
    'voucher.assigned_to_family_member',
    'voucher_issuance',
    target_voucher_id,
    to_jsonb(voucher),
    jsonb_build_object('beneficiary_id', target_child_id, 'family_id', target_family_id, 'assignment_id', assignment_id),
    assignment_note
  );

  return assignment_id;
end;
$$;

create or replace function public.accept_family_invitation(target_invitation_id uuid)
returns uuid
language sql
security invoker
set search_path = public, extensions
as $$
  select app_private.accept_family_invitation(target_invitation_id);
$$;

create or replace function public.assign_voucher_to_family_member(
  target_voucher_id uuid,
  target_child_id uuid,
  assignment_note text default null
)
returns uuid
language sql
security invoker
set search_path = public, extensions
as $$
  select app_private.assign_voucher_to_family_member(target_voucher_id, target_child_id, assignment_note);
$$;

revoke all on function public.invite_family_guardian(uuid, text, text, text) from public;
revoke all on function public.accept_family_invitation(uuid) from public;
revoke all on function public.assign_voucher_to_family_member(uuid, uuid, text) from public;
revoke all on function app_private.accept_family_invitation(uuid) from public;
revoke all on function app_private.assign_voucher_to_family_member(uuid, uuid, text) from public;
grant execute on function app_private.accept_family_invitation(uuid) to authenticated;
grant execute on function app_private.assign_voucher_to_family_member(uuid, uuid, text) to authenticated;
grant execute on function public.invite_family_guardian(uuid, text, text, text) to authenticated;
grant execute on function public.accept_family_invitation(uuid) to authenticated;
grant execute on function public.assign_voucher_to_family_member(uuid, uuid, text) to authenticated;

grant select, insert, update on table public.family_relationship_invitations to authenticated;
grant select on table public.family_voucher_assignments to authenticated;
grant select on table public.family_voucher_assignments to service_role;
