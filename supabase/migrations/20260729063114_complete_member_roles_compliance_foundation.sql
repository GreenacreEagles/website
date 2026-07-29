-- Forward-only completion of roles, permissions and compliance. No destructive consolidation.

alter table public.roles add column if not exists is_active boolean not null default true;
alter table public.roles add column if not exists role_kind text not null default 'global';
alter table public.permissions add column if not exists is_active boolean not null default true;

do $$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.roles'::regclass and conname='roles_role_kind_check') then
  alter table public.roles add constraint roles_role_kind_check check(role_kind in ('global','technical','deprecated')) not valid;
  alter table public.roles validate constraint roles_role_kind_check;
 end if;
end $$;

insert into public.permissions(key,name,description,is_active) values
 ('roles.manage','Manage roles','Assign and revoke supported global roles.',true),
 ('registrations.view','View registrations','View registration records.',true),
 ('registrations.manage','Manage registrations','Manage registration records.',true),
 ('volunteers.view','View volunteers','View volunteer status and review queues.',true),
 ('wwcc.view','View WWCC records','View sensitive WWCC records where authorised.',true),
 ('wwcc.verify','Verify WWCC records','Record external NSW OCG verification outcomes.',true),
 ('team_memberships.manage','Manage team memberships','Manage player and staff team assignments.',true)
on conflict(key) do update set name=excluded.name,description=excluded.description,is_active=true;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r join public.permissions p on p.key in
 ('registrations.view','registrations.manage','volunteers.view','wwcc.view','wwcc.verify','team_memberships.manage')
where r.key in ('registrar','club_administrator','club_admin','super_administrator') on conflict do nothing;

create table if not exists public.member_compliance(
 user_id uuid primary key references public.profiles(id) on delete cascade,
 volunteer_status text not null default 'pending' check(volunteer_status in ('pending','approved','suspended','expired','rejected')),
 volunteer_approved_at timestamptz, volunteer_approved_by uuid references public.profiles(id) on delete set null,
 volunteer_reason text, volunteer_notes text, wwcc_number text,
 wwcc_status text not null default 'not_supplied' check(wwcc_status in ('not_supplied','pending_verification','verified','rejected','expired')),
 wwcc_expiry_date date, wwcc_verified_at timestamptz, wwcc_verified_by uuid references public.profiles(id) on delete set null,
 wwcc_verification_name text, wwcc_notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.member_compliance enable row level security;
create index if not exists member_compliance_volunteer_status_idx on public.member_compliance(volunteer_status);
create index if not exists member_compliance_wwcc_status_expiry_idx on public.member_compliance(wwcc_status,wwcc_expiry_date);
insert into public.member_compliance(user_id) select id from public.profiles on conflict(user_id) do nothing;
drop trigger if exists member_compliance_set_updated_at on public.member_compliance;
create trigger member_compliance_set_updated_at before update on public.member_compliance for each row execute function app_private.set_updated_at();
revoke all on public.member_compliance from anon,authenticated;
grant select on public.member_compliance to authenticated;
grant select,insert,update,delete on public.member_compliance to service_role;
drop policy if exists member_compliance_read on public.member_compliance;
create policy member_compliance_read on public.member_compliance for select to authenticated using(
 user_id=(select auth.uid()) or app_private.has_permission('volunteers.view') or app_private.has_permission('volunteers.manage')
 or app_private.has_permission('wwcc.view') or app_private.has_permission('wwcc.verify')
);
