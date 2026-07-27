-- Consolidate global roles, team-scoped positions, volunteer approval and WWCC compliance.
-- Existing assignments are retained as history and mapped to the closest supported model.

alter table public.roles add column if not exists is_active boolean not null default true;
alter table public.roles add column if not exists role_kind text not null default 'global';
alter table public.roles drop constraint if exists roles_role_kind_check;
alter table public.roles add constraint roles_role_kind_check check (role_kind in ('global','technical','deprecated'));
alter table public.permissions add column if not exists is_active boolean not null default true;
alter table public.team_staff add column if not exists assigned_by uuid references public.profiles(id) on delete set null;
alter table public.team_players add column if not exists assigned_by uuid references public.profiles(id) on delete set null;

update public.roles set key='club_admin',name='Club Admin',description='Full access to all club administration.',is_active=true,role_kind='global',may_request=false,requires_team_scope=false,requires_season_scope=false,sort_order=20 where key='club_administrator';

insert into public.roles(key,name,description,is_system,is_sensitive,may_request,requires_team_scope,requires_season_scope,requires_super_admin_approval,sort_order,is_active,role_kind)
values
 ('general_user','General User','Standard member portal access.',true,false,false,false,false,false,10,true,'global'),
 ('club_admin','Club Admin','Full access to all club administration.',true,true,false,false,false,false,20,true,'global'),
 ('registrar','Registrar','Registrations, players, volunteers and team assignments.',true,true,false,false,false,false,30,true,'global'),
 ('content_editor','Content Editor','News, socials, resources and sponsors.',true,false,false,false,false,false,40,true,'global'),
 ('event_manager','Event Manager','Club events and event registrations.',true,false,false,false,false,false,50,true,'global'),
 ('merchandise_manager','Merchandise Manager','Merchandise products and orders.',true,true,false,false,false,false,60,true,'global'),
 ('canteen_manager','Canteen Manager','Canteen products, orders and reporting.',true,true,false,false,false,false,70,true,'global'),
 ('canteen_staff','Canteen Staff','Canteen order preparation and QR collection.',true,true,false,false,false,false,80,true,'global'),
 ('super_administrator','Super Administrator','Technical bootstrap and emergency platform ownership.',true,true,false,false,false,true,1000,true,'technical')
on conflict(key) do update set name=excluded.name,description=excluded.description,is_system=excluded.is_system,is_sensitive=excluded.is_sensitive,may_request=false,requires_team_scope=false,requires_season_scope=false,requires_super_admin_approval=excluded.requires_super_admin_approval,sort_order=excluded.sort_order,is_active=true,role_kind=excluded.role_kind;

do $$ declare old_id uuid; new_id uuid; begin
 select id into old_id from public.roles where key='canteen_worker'; select id into new_id from public.roles where key='canteen_staff';
 if old_id is not null and new_id is not null then
  update public.user_role_assignments o set status='revoked',revoked_at=coalesce(revoked_at,now()),reason=coalesce(reason,'Merged into Canteen Staff'),updated_at=now()
  where role_id=old_id and exists(select 1 from public.user_role_assignments n where n.user_id=o.user_id and n.role_id=new_id and n.status='active' and n.revoked_at is null);
  update public.user_role_assignments set role_id=new_id,reason=coalesce(reason,'Migrated from Canteen Worker') where role_id=old_id and status<>'revoked';
 end if;
end $$;

do $$ declare old_id uuid; new_id uuid; begin
 select id into old_id from public.roles where key='volunteer_coordinator'; select id into new_id from public.roles where key='registrar';
 if old_id is not null and new_id is not null then
  update public.user_role_assignments o set status='revoked',revoked_at=coalesce(revoked_at,now()),reason=coalesce(reason,'Merged into Registrar'),updated_at=now()
  where role_id=old_id and exists(select 1 from public.user_role_assignments n where n.user_id=o.user_id and n.role_id=new_id and n.status='active' and n.revoked_at is null);
  update public.user_role_assignments set role_id=new_id,reason=coalesce(reason,'Migrated from Volunteer Coordinator') where role_id=old_id and status<>'revoked';
 end if;
end $$;

insert into public.team_staff(team_id,user_id,staff_role,starts_on,ends_on,status,assigned_by,created_at,updated_at)
select ura.team_id,ura.user_id,case when r.key in ('coach','assistant_coach') then 'coach' else 'team_manager' end,ura.starts_at::date,ura.ends_at::date,case when ura.status='active' and ura.revoked_at is null then 'active' else 'inactive' end,ura.assigned_by,ura.created_at,ura.updated_at
from public.user_role_assignments ura join public.roles r on r.id=ura.role_id where r.key in ('coach','assistant_coach','team_manager') and ura.team_id is not null
on conflict(team_id,user_id,staff_role) do update set starts_on=coalesce(public.team_staff.starts_on,excluded.starts_on),ends_on=coalesce(excluded.ends_on,public.team_staff.ends_on),assigned_by=coalesce(public.team_staff.assigned_by,excluded.assigned_by),updated_at=greatest(public.team_staff.updated_at,excluded.updated_at);

insert into public.player_records(user_id,season_id,registration_status,created_at,updated_at)
select distinct ura.user_id,coalesce(ura.season_id,t.season_id),'registered',ura.created_at,ura.updated_at from public.user_role_assignments ura join public.roles r on r.id=ura.role_id join public.teams t on t.id=ura.team_id where r.key='player' and ura.team_id is not null
on conflict(user_id,season_id) do nothing;
insert into public.team_players(team_id,player_id,starts_on,ends_on,status,assigned_by,created_at,updated_at)
select ura.team_id,pr.id,ura.starts_at::date,ura.ends_at::date,case when ura.status='active' and ura.revoked_at is null then 'active' else 'inactive' end,ura.assigned_by,ura.created_at,ura.updated_at
from public.user_role_assignments ura join public.roles r on r.id=ura.role_id join public.teams t on t.id=ura.team_id join public.player_records pr on pr.user_id=ura.user_id and pr.season_id=coalesce(ura.season_id,t.season_id)
where r.key='player' and ura.team_id is not null
on conflict(team_id,player_id) do update set starts_on=coalesce(public.team_players.starts_on,excluded.starts_on),ends_on=coalesce(excluded.ends_on,public.team_players.ends_on),assigned_by=coalesce(public.team_players.assigned_by,excluded.assigned_by),updated_at=greatest(public.team_players.updated_at,excluded.updated_at);

update public.user_role_assignments ura set status='revoked',revoked_at=coalesce(revoked_at,now()),reason=coalesce(reason,'Migrated to a team-scoped position'),updated_at=now() from public.roles r where r.id=ura.role_id and r.key in ('player','coach','assistant_coach','team_manager') and ura.status<>'revoked';
update public.team_staff o set status='inactive',updated_at=now() where o.staff_role='assistant_coach' and exists(select 1 from public.team_staff c where c.team_id=o.team_id and c.user_id=o.user_id and c.staff_role='coach');
update public.team_staff set staff_role='coach',updated_at=now() where staff_role='assistant_coach' and status='active';
update public.team_staff set status='inactive',updated_at=now() where staff_role='trainer' and status='active';

update public.roles set is_active=false,role_kind='deprecated',may_request=false where key not in ('general_user','club_admin','registrar','content_editor','event_manager','merchandise_manager','canteen_manager','canteen_staff','super_administrator');
update public.user_role_assignments ura set status='revoked',revoked_at=coalesce(revoked_at,now()),reason=coalesce(reason,'Obsolete global role retired during consolidation'),updated_at=now() from public.roles r where r.id=ura.role_id and not r.is_active and ura.status<>'revoked';
insert into public.permissions(key,name,description,is_active) values
 ('roles.manage','Manage roles','Assign and revoke supported global roles.',true),('registrations.view','View registrations','View player and member registration records.',true),('registrations.manage','Manage registrations','Manage registrations, transfers and team placement.',true),('team_memberships.manage','Manage team assignments','Assign and deactivate Player, Coach and Team Manager positions.',true),('volunteers.view','View volunteer compliance','View volunteer approval status.',true),('wwcc.view','View WWCC compliance','View protected WWCC status and permitted verification details.',true),('wwcc.verify','Verify WWCC compliance','Record and verify WWCC details.',true),('content.view','View content administration','View editable club content.',true),('events.view','View event administration','View event registrations and operations.',true),('merchandise.view','View merchandise operations','View merchandise products, orders and reports.',true),('canteen.orders.view','View canteen orders','View limited information needed for canteen operations.',true),('canteen.orders.fulfil','Fulfil canteen orders','Prepare, ready and collect active canteen orders.',true),('canteen.products.manage','Manage canteen products','Manage canteen products, prices, stock and availability.',true),('canteen.reports.view','View canteen reports','View canteen operational and sales reports.',true)
on conflict(key) do update set name=excluded.name,description=excluded.description,is_active=true;
update public.permissions set is_active=false where key in ('roles.review','team_access.review');

delete from public.role_permissions where role_id in(select id from public.roles where key in ('general_user','club_admin','registrar','content_editor','event_manager','merchandise_manager','canteen_manager','canteen_staff','super_administrator'));
insert into public.role_permissions(role_id,permission_id) select r.id,p.id from public.roles r cross join public.permissions p where r.key='club_admin' and p.key<>'*' and p.is_active on conflict do nothing;
insert into public.role_permissions(role_id,permission_id) select r.id,p.id from public.roles r join public.permissions p on p.key='*' where r.key='super_administrator' on conflict do nothing;
with matrix(role_key,permission_key) as (values
 ('general_user','merchandise.store_access'),
 ('registrar','users.read'),('registrar','players.manage'),('registrar','families.manage'),('registrar','families.invite'),('registrar','registrations.view'),('registrar','registrations.manage'),('registrar','teams.read'),('registrar','team_memberships.manage'),('registrar','volunteers.view'),('registrar','volunteers.manage'),('registrar','wwcc.view'),('registrar','wwcc.verify'),
 ('content_editor','content.view'),('content_editor','content.manage'),('content_editor','social_profiles.view'),('content_editor','social_profiles.manage'),('content_editor','social_posts.view'),('content_editor','social_posts.manage'),('content_editor','sponsors.view'),('content_editor','sponsors.manage'),('content_editor','coaching_resources.read'),('content_editor','coaching_resources.manage'),
 ('event_manager','events.view'),('event_manager','events.manage'),('event_manager','events.orders.read'),('event_manager','events.tickets.scan'),('event_manager','events.tickets.redeem'),
 ('merchandise_manager','merchandise.view'),('merchandise_manager','merchandise.manage'),('merchandise_manager','shop.merchandise.fulfil'),('merchandise_manager','shop.orders.view'),('merchandise_manager','shop.orders.manage'),
 ('canteen_manager','canteen.manage'),('canteen_manager','canteen.products.manage'),('canteen_manager','canteen.orders.view'),('canteen_manager','canteen.orders.manage'),('canteen_manager','canteen.orders.fulfil'),('canteen_manager','canteen.reports.view'),('canteen_manager','canteen.vouchers.manage'),('canteen_manager','canteen.vouchers.redeem'),('canteen_manager','canteen.vouchers.reverse'),('canteen_manager','shop.canteen.scan'),('canteen_manager','shop.canteen.redeem'),('canteen_manager','wallet.read'),
 ('canteen_staff','canteen.orders.view'),('canteen_staff','canteen.orders.fulfil'),('canteen_staff','canteen.vouchers.redeem'),('canteen_staff','shop.canteen.scan'),('canteen_staff','shop.canteen.redeem')
) insert into public.role_permissions(role_id,permission_id) select r.id,p.id from matrix m join public.roles r on r.key=m.role_key join public.permissions p on p.key=m.permission_key where p.is_active on conflict do nothing;

with ranked as (select id,row_number() over(partition by user_id,role_id order by created_at,id) rn from public.user_role_assignments where status='active' and revoked_at is null and team_id is null and season_id is null)
update public.user_role_assignments ura set status='revoked',revoked_at=now(),reason=coalesce(reason,'Duplicate active assignment consolidated'),updated_at=now() from ranked where ranked.id=ura.id and ranked.rn>1;
create unique index if not exists user_role_assignments_one_active_global on public.user_role_assignments(user_id,role_id) where status='active' and revoked_at is null and team_id is null and season_id is null;
create index if not exists team_staff_user_active_idx on public.team_staff(user_id,team_id) where status='active';
create index if not exists team_players_player_active_idx on public.team_players(player_id,team_id) where status='active';

create table if not exists public.member_compliance(
 user_id uuid primary key references public.profiles(id) on delete cascade,
 volunteer_status text not null default 'pending' check(volunteer_status in ('pending','approved','suspended','expired','rejected')),
 volunteer_approved_at timestamptz,volunteer_approved_by uuid references public.profiles(id) on delete set null,
 volunteer_reason text,volunteer_notes text,wwcc_number text,
 wwcc_status text not null default 'not_supplied' check(wwcc_status in ('not_supplied','pending_verification','verified','expired','exempt','rejected')),
 wwcc_expiry_date date,wwcc_verified_at timestamptz,wwcc_verified_by uuid references public.profiles(id) on delete set null,
 wwcc_verification_name text,wwcc_notes text,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
alter table public.member_compliance enable row level security;
create index if not exists member_compliance_volunteer_status_idx on public.member_compliance(volunteer_status);
create index if not exists member_compliance_wwcc_status_expiry_idx on public.member_compliance(wwcc_status,wwcc_expiry_date);
insert into public.member_compliance(user_id) select id from public.profiles on conflict(user_id) do nothing;
drop trigger if exists member_compliance_set_updated_at on public.member_compliance;
create trigger member_compliance_set_updated_at before update on public.member_compliance for each row execute function app_private.set_updated_at();
revoke all on public.member_compliance from anon,authenticated;
grant select on public.member_compliance to authenticated;
drop policy if exists member_compliance_read on public.member_compliance;
create policy member_compliance_read on public.member_compliance for select to authenticated using(user_id=(select auth.uid()) or app_private.has_permission('volunteers.view') or app_private.has_permission('volunteers.manage') or app_private.has_permission('wwcc.view') or app_private.has_permission('wwcc.verify'));

create or replace function app_private.has_permission(permission_key text,target_team_id uuid default null,target_season_id uuid default null)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.user_role_assignments ura join public.roles r on r.id=ura.role_id and r.is_active join public.role_permissions rp on rp.role_id=r.id join public.permissions p on p.id=rp.permission_id and p.is_active where ura.user_id=(select auth.uid()) and ura.status='active' and ura.revoked_at is null and ura.starts_at<=now() and (ura.ends_at is null or ura.ends_at>now()) and (p.key=permission_key or p.key='*') and (target_team_id is null or ura.team_id is null or ura.team_id=target_team_id) and (target_season_id is null or ura.season_id is null or ura.season_id=target_season_id) and (r.key<>'canteen_staff' or exists(select 1 from public.member_compliance mc where mc.user_id=ura.user_id and mc.volunteer_status='approved')));
$$;
revoke all on function app_private.has_permission(text,uuid,uuid) from public,anon;
grant execute on function app_private.has_permission(text,uuid,uuid) to authenticated,service_role;

create or replace function public.has_any_permission(required_keys text[],target_team_id uuid default null,target_season_id uuid default null)
returns boolean language sql stable security definer set search_path='' as $$
 select (select auth.uid()) is not null and coalesce(cardinality(required_keys),0)>0 and not exists(select 1 from public.managed_child_accounts c where c.child_user_id=(select auth.uid())) and exists(select 1 from public.user_role_assignments ura join public.roles r on r.id=ura.role_id and r.is_active join public.role_permissions rp on rp.role_id=r.id join public.permissions p on p.id=rp.permission_id and p.is_active where ura.user_id=(select auth.uid()) and ura.status='active' and ura.revoked_at is null and ura.starts_at<=now() and (ura.ends_at is null or ura.ends_at>now()) and (p.key='*' or p.key=any(required_keys)) and (target_team_id is null or ura.team_id is null or ura.team_id=target_team_id) and (target_season_id is null or ura.season_id is null or ura.season_id=target_season_id) and (r.key<>'canteen_staff' or exists(select 1 from public.member_compliance mc where mc.user_id=ura.user_id and mc.volunteer_status='approved')));
$$;
revoke all on function public.has_any_permission(text[],uuid,uuid) from public,anon;
grant execute on function public.has_any_permission(text[],uuid,uuid) to authenticated,service_role;
create or replace function app_private.can_assign_role(target_role_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select case when r.key='super_administrator' then app_private.has_permission('*') when r.key='general_user' then false else app_private.has_permission('roles.assign') or app_private.has_permission('roles.manage') end from public.roles r where r.id=target_role_id and r.is_active and r.role_kind in ('global','technical');
$$;
revoke all on function app_private.can_assign_role(uuid) from public,anon,authenticated;
grant execute on function app_private.can_assign_role(uuid) to service_role;

create or replace function app_private.can_access_team(target_team_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select app_private.has_permission('club_structure.manage') or app_private.has_permission('team_memberships.manage')
 or exists(select 1 from public.team_staff ts where ts.team_id=target_team_id and ts.user_id=(select auth.uid()) and ts.status='active' and (ts.starts_on is null or ts.starts_on<=current_date) and (ts.ends_on is null or ts.ends_on>=current_date))
 or exists(select 1 from public.team_players tp join public.player_records pr on pr.id=tp.player_id where tp.team_id=target_team_id and tp.status='active' and pr.user_id=(select auth.uid()))
 or exists(select 1 from public.team_players tp join public.player_records pr on pr.id=tp.player_id join public.family_members cm on cm.user_id=pr.user_id and cm.status='active' join public.family_members gm on gm.family_id=cm.family_id and gm.status='active' where tp.team_id=target_team_id and tp.status='active' and gm.user_id=(select auth.uid()) and gm.relationship in ('parent','guardian','carer'));
$$;
revoke all on function app_private.can_access_team(uuid) from public,anon;
grant execute on function app_private.can_access_team(uuid) to authenticated,service_role;

create or replace function app_private.can_manage_team_operations(target_team_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select app_private.has_permission('club_structure.manage') or exists(select 1 from public.team_staff ts join public.member_compliance mc on mc.user_id=ts.user_id where ts.team_id=target_team_id and ts.user_id=(select auth.uid()) and ts.status='active' and ts.staff_role in ('coach','team_manager') and (ts.starts_on is null or ts.starts_on<=current_date) and (ts.ends_on is null or ts.ends_on>=current_date) and mc.volunteer_status='approved' and mc.wwcc_status in ('verified','exempt') and (mc.wwcc_status='exempt' or mc.wwcc_expiry_date is null or mc.wwcc_expiry_date>=current_date));
$$;
revoke all on function app_private.can_manage_team_operations(uuid) from public,anon;
grant execute on function app_private.can_manage_team_operations(uuid) to authenticated,service_role;

insert into public.user_role_assignments(user_id,role_id,status,reason)
select p.id,r.id,'active','Automatic general-user provisioning' from public.profiles p cross join public.roles r where r.key='general_user' and not exists(select 1 from public.user_role_assignments ura where ura.user_id=p.id and ura.role_id=r.id and ura.status='active' and ura.revoked_at is null and ura.team_id is null and ura.season_id is null);

create or replace function app_private.handle_new_user()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,full_name,email,terms_accepted_at,privacy_accepted_at) values(new.id,coalesce(new.raw_user_meta_data->>'full_name',''),new.email,case when coalesce(new.raw_user_meta_data->>'terms_accepted','false')='true' then now() end,case when coalesce(new.raw_user_meta_data->>'privacy_accepted','false')='true' then now() end)
 on conflict(id) do update set email=excluded.email,full_name=case when public.profiles.full_name='' then excluded.full_name else public.profiles.full_name end;
 insert into public.member_compliance(user_id) values(new.id) on conflict(user_id) do nothing;
 insert into public.user_role_assignments(user_id,role_id,status,reason) select new.id,r.id,'active','Automatic general-user provisioning' from public.roles r where r.key='general_user'
 on conflict(user_id,role_id) where status='active' and revoked_at is null and team_id is null and season_id is null do nothing;
 return new;
end;
$$;

create or replace function public.assign_user_role(target_user_id uuid,target_role_id uuid,target_team_id uuid default null,target_season_id uuid default null,starts_at timestamptz default now(),ends_at timestamptz default null,assignment_reason text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare assignment_id uuid; target_role public.roles%rowtype;
begin
 if auth.uid() is null then raise exception 'You must be signed in'; end if;
 if auth.uid()=target_user_id and not app_private.has_permission('*') then raise exception 'You cannot change your own role access'; end if;
 select * into target_role from public.roles where id=target_role_id and is_active and role_kind in ('global','technical');
 if not found then raise exception 'Supported global role not found'; end if;
 if target_role.key='general_user' then raise exception 'General User is assigned automatically'; end if;
 if target_team_id is not null or target_season_id is not null then raise exception 'Global roles cannot be scoped to a team or season'; end if;
 if not app_private.can_assign_role(target_role_id) then raise exception 'You do not have permission to assign this role'; end if;
 if ends_at is not null and ends_at<=starts_at then raise exception 'Expiry must be after the start date'; end if;
 if coalesce(length(trim(assignment_reason)),0)<10 then raise exception 'A clear assignment reason is required'; end if;
 insert into public.user_role_assignments(user_id,role_id,starts_at,ends_at,status,reason,assigned_by) values(target_user_id,target_role_id,coalesce(starts_at,now()),ends_at,'active',trim(assignment_reason),auth.uid()) returning id into assignment_id;
 perform app_private.write_audit_log('role_assignment.created','user_role_assignment',assignment_id,null,jsonb_build_object('user_id',target_user_id,'role_key',target_role.key),trim(assignment_reason)); return assignment_id;
exception when unique_violation then raise exception 'This user already has this active global role';
end;
$$;

create or replace function public.revoke_user_role(target_assignment_id uuid,revocation_reason text)
returns void language plpgsql security definer set search_path='' as $$
declare before_row public.user_role_assignments%rowtype; role_key text; remaining_super_admins int;
begin
 if auth.uid() is null then raise exception 'You must be signed in'; end if;
 select ura.* into before_row from public.user_role_assignments ura where ura.id=target_assignment_id and ura.status='active' for update;
 if not found then raise exception 'Active role assignment not found'; end if;
 select key into role_key from public.roles where id=before_row.role_id;
 if role_key='general_user' then raise exception 'General User cannot be removed'; end if;
 if not app_private.can_assign_role(before_row.role_id) then raise exception 'You do not have permission to revoke this role'; end if;
 if before_row.user_id=auth.uid() and not app_private.has_permission('*') then raise exception 'You cannot revoke your own administration access'; end if;
 if coalesce(length(trim(revocation_reason)),0)<10 then raise exception 'A clear revocation reason is required'; end if;
 if role_key='super_administrator' then select count(*) into remaining_super_admins from public.user_role_assignments ura join public.roles r on r.id=ura.role_id where r.key='super_administrator' and ura.status='active' and ura.revoked_at is null and ura.id<>target_assignment_id; if remaining_super_admins<1 then raise exception 'Cannot remove the final active Super Administrator'; end if; end if;
 update public.user_role_assignments set status='revoked',revoked_by=auth.uid(),revoked_at=now(),reason=trim(revocation_reason),updated_at=now() where id=target_assignment_id;
 perform app_private.write_audit_log('role_assignment.revoked','user_role_assignment',target_assignment_id,to_jsonb(before_row),null,trim(revocation_reason));
end;
$$;

create or replace function public.update_member_compliance(target_user_id uuid,target_volunteer_status text,target_volunteer_reason text,target_volunteer_notes text,target_wwcc_number text,target_wwcc_status text,target_wwcc_expiry_date date,target_wwcc_verification_name text,target_wwcc_notes text)
returns void language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); before_row public.member_compliance%rowtype; after_row public.member_compliance%rowtype;
begin
 if actor is null or not(app_private.has_permission('volunteers.manage') and app_private.has_permission('wwcc.verify')) then raise exception 'Not authorised'; end if;
 if target_volunteer_status not in('pending','approved','suspended','expired','rejected') then raise exception 'Invalid volunteer status'; end if;
 if target_wwcc_status not in('not_supplied','pending_verification','verified','expired','exempt','rejected') then raise exception 'Invalid WWCC status'; end if;
 select * into before_row from public.member_compliance where user_id=target_user_id for update;
 if not found then insert into public.member_compliance(user_id) values(target_user_id) returning * into before_row; end if;
 update public.member_compliance set volunteer_status=target_volunteer_status,volunteer_approved_at=case when target_volunteer_status='approved' then coalesce(volunteer_approved_at,now()) else volunteer_approved_at end,volunteer_approved_by=case when target_volunteer_status='approved' then actor else volunteer_approved_by end,volunteer_reason=nullif(trim(coalesce(target_volunteer_reason,'')),''),volunteer_notes=nullif(trim(coalesce(target_volunteer_notes,'')),''),wwcc_number=nullif(upper(regexp_replace(trim(coalesce(target_wwcc_number,'')),'\s+','','g')),''),wwcc_status=target_wwcc_status,wwcc_expiry_date=target_wwcc_expiry_date,wwcc_verified_at=case when target_wwcc_status in('verified','exempt') then coalesce(wwcc_verified_at,now()) else wwcc_verified_at end,wwcc_verified_by=case when target_wwcc_status in('verified','exempt') then actor else wwcc_verified_by end,wwcc_verification_name=nullif(trim(coalesce(target_wwcc_verification_name,'')),''),wwcc_notes=nullif(trim(coalesce(target_wwcc_notes,'')),'') where user_id=target_user_id returning * into after_row;
 perform app_private.write_audit_log('member_compliance.updated','member_compliance',target_user_id,jsonb_build_object('volunteer_status',before_row.volunteer_status,'wwcc_status',before_row.wwcc_status,'wwcc_expiry_date',before_row.wwcc_expiry_date,'wwcc_last4',right(coalesce(before_row.wwcc_number,''),4)),jsonb_build_object('volunteer_status',after_row.volunteer_status,'wwcc_status',after_row.wwcc_status,'wwcc_expiry_date',after_row.wwcc_expiry_date,'wwcc_last4',right(coalesce(after_row.wwcc_number,''),4)),coalesce(target_volunteer_reason,'Compliance record updated'));
end;
$$;
revoke all on function public.update_member_compliance(uuid,text,text,text,text,text,date,text,text) from public,anon;
grant execute on function public.update_member_compliance(uuid,text,text,text,text,text,date,text,text) to authenticated,service_role;
create or replace function public.save_team_assignment(target_user_id uuid,target_team_id uuid,target_position text,target_status text default 'active',target_starts_on date default null,target_ends_on date default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); team_season uuid; saved_id uuid; player_record_id uuid; compliance public.member_compliance%rowtype;
begin
 if actor is null or not(app_private.has_permission('team_memberships.manage') or app_private.has_permission('club_structure.manage')) then raise exception 'Not authorised'; end if;
 if target_position not in('player','coach','team_manager') then raise exception 'Unsupported team position'; end if;
 if target_status not in('active','inactive','left') then raise exception 'Invalid assignment status'; end if;
 if target_ends_on is not null and target_starts_on is not null and target_ends_on<target_starts_on then raise exception 'End date must follow start date'; end if;
 select season_id into team_season from public.teams where id=target_team_id; if team_season is null then raise exception 'Team not found'; end if;
 if not exists(select 1 from public.profiles where id=target_user_id) then raise exception 'User not found'; end if;
 if target_position in('coach','team_manager') and target_status='active' then select * into compliance from public.member_compliance where user_id=target_user_id; if compliance.user_id is null or compliance.volunteer_status<>'approved' or compliance.wwcc_status not in('verified','exempt') or (compliance.wwcc_status='verified' and compliance.wwcc_expiry_date is not null and compliance.wwcc_expiry_date<current_date) then raise exception 'Coach and Team Manager assignments require approved volunteer and current verified or exempt WWCC status'; end if; end if;
 if target_position='player' then
  insert into public.player_records(user_id,season_id,registration_status) values(target_user_id,team_season,'registered') on conflict(user_id,season_id) do update set updated_at=now() returning id into player_record_id;
  insert into public.team_players(team_id,player_id,starts_on,ends_on,status,assigned_by) values(target_team_id,player_record_id,target_starts_on,target_ends_on,target_status,actor)
  on conflict(team_id,player_id) do update set starts_on=excluded.starts_on,ends_on=excluded.ends_on,status=excluded.status,assigned_by=actor,updated_at=now() returning id into saved_id;
 else
  insert into public.team_staff(team_id,user_id,staff_role,starts_on,ends_on,status,assigned_by) values(target_team_id,target_user_id,target_position,target_starts_on,target_ends_on,target_status,actor)
  on conflict(team_id,user_id,staff_role) do update set starts_on=excluded.starts_on,ends_on=excluded.ends_on,status=excluded.status,assigned_by=actor,updated_at=now() returning id into saved_id;
 end if;
 perform app_private.write_audit_log('team_assignment.saved','team_assignment',saved_id,null,jsonb_build_object('user_id',target_user_id,'team_id',target_team_id,'position',target_position,'status',target_status),null); return saved_id;
end;
$$;
revoke all on function public.save_team_assignment(uuid,uuid,text,text,date,date) from public,anon;
grant execute on function public.save_team_assignment(uuid,uuid,text,text,date,date) to authenticated,service_role;

drop policy if exists team_manage_admin_staff_insert on public.team_staff; drop policy if exists team_manage_admin_staff_update on public.team_staff; drop policy if exists team_manage_admin_staff_delete on public.team_staff;
create policy team_manage_admin_staff_insert on public.team_staff for insert to authenticated with check(app_private.has_permission('team_memberships.manage') or app_private.has_permission('club_structure.manage'));
create policy team_manage_admin_staff_update on public.team_staff for update to authenticated using(app_private.has_permission('team_memberships.manage') or app_private.has_permission('club_structure.manage')) with check(app_private.has_permission('team_memberships.manage') or app_private.has_permission('club_structure.manage'));
create policy team_manage_admin_staff_delete on public.team_staff for delete to authenticated using(app_private.has_permission('team_memberships.manage') or app_private.has_permission('club_structure.manage'));
drop policy if exists team_players_manage_admin_insert on public.team_players; drop policy if exists team_players_manage_admin_update on public.team_players; drop policy if exists team_players_manage_admin_delete on public.team_players;
create policy team_players_manage_admin_insert on public.team_players for insert to authenticated with check(app_private.has_permission('team_memberships.manage') or app_private.has_permission('club_structure.manage'));
create policy team_players_manage_admin_update on public.team_players for update to authenticated using(app_private.has_permission('team_memberships.manage') or app_private.has_permission('club_structure.manage')) with check(app_private.has_permission('team_memberships.manage') or app_private.has_permission('club_structure.manage'));
create policy team_players_manage_admin_delete on public.team_players for delete to authenticated using(app_private.has_permission('team_memberships.manage') or app_private.has_permission('club_structure.manage'));

drop view if exists public.role_catalog;
create view public.role_catalog with(security_invoker=true) as select r.id,r.key,r.name,r.description,r.is_system,r.is_sensitive,r.may_request,r.requires_team_scope,r.requires_season_scope,r.requires_super_admin_approval,r.sort_order,r.is_active,r.role_kind,coalesce(jsonb_agg(jsonb_build_object('key',p.key,'name',p.name,'description',p.description) order by p.key) filter(where p.id is not null and p.is_active),'[]'::jsonb) permissions from public.roles r left join public.role_permissions rp on rp.role_id=r.id left join public.permissions p on p.id=rp.permission_id where r.is_active and(r.role_kind='global' or(r.role_kind='technical' and app_private.has_permission('*'))) group by r.id;
grant select on public.role_catalog to authenticated,service_role;

create or replace function public.admin_dashboard_summary()
returns jsonb language sql stable security definer set search_path=pg_catalog,public,app_private,extensions as $$
 select jsonb_strip_nulls(jsonb_build_object(
  'total_users',case when public.has_any_permission(array['users.read']) then(select count(*) from public.profiles) end,
  'new_users',case when public.has_any_permission(array['users.read']) then(select count(*) from public.profiles where created_at>=now()-interval '30 days') end,
  'active_players',case when public.has_any_permission(array['registrations.view','players.manage']) then(select count(*) from public.player_records where registration_status='registered') end,
  'active_families',case when public.has_any_permission(array['registrations.view','families.manage']) then(select count(*) from public.families) end,
  'teams',case when public.has_any_permission(array['team_memberships.manage','club_structure.manage']) then(select count(*) from public.teams where status='active') end,
  'active_volunteers',case when public.has_any_permission(array['volunteers.view']) then(select count(*) from public.member_compliance where volunteer_status='approved') end,
  'upcoming_events',case when public.has_any_permission(array['events.view','events.manage']) then(select count(*) from public.club_events where status='active' and starts_at>=now()) end,
  'event_registrations',case when public.has_any_permission(array['events.view','events.manage']) then(select count(*) from public.event_registrations where status in('interest','confirmed','waitlisted')) end,
  'canteen_orders_today',case when public.has_any_permission(array['canteen.reports.view','canteen.manage']) then(select count(*) from public.canteen_orders where created_at>=now()-interval '24 hours') end,
  'canteen_orders_open',case when public.has_any_permission(array['canteen.orders.manage','canteen.manage']) then(select count(*) from public.canteen_orders where order_status in('new','accepted','preparing')) end,
  'canteen_orders_ready',case when public.has_any_permission(array['canteen.orders.manage','canteen.manage']) then(select count(*) from public.canteen_orders where order_status='ready_for_pickup') end,
  'active_vouchers',case when public.has_any_permission(array['wallet.read','canteen.manage']) then(select count(*) from public.voucher_issuances where status='active') end,
  'expiring_vouchers',case when public.has_any_permission(array['wallet.read','canteen.manage']) then(select count(*) from public.voucher_issuances where status='active' and expires_at<=now()+interval '14 days') end,
  'active_news',case when public.has_any_permission(array['content.view','content.manage']) then(select count(*) from public.content_articles where workflow_status='active') end
 ));
$$;
revoke all on function public.admin_dashboard_summary() from public,anon;
grant execute on function public.admin_dashboard_summary() to authenticated,service_role;
create or replace function public.get_portal_context()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, app_private, extensions
as $$
  with caller as (
    select (select auth.uid()) as user_id
  ),
  profile_data as (
    select jsonb_build_object(
      'id', profile.id,
      'full_name', profile.full_name,
      'preferred_name', profile.preferred_name,
      'mobile', profile.mobile,
      'relationship_to_club', profile.relationship_to_club,
      'emergency_contact_name', profile.emergency_contact_name,
      'emergency_contact_phone', profile.emergency_contact_phone,
      'communication_email', profile.communication_email,
      'communication_sms', profile.communication_sms,
      'terms_accepted_at', profile.terms_accepted_at,
      'privacy_accepted_at', profile.privacy_accepted_at,
      'onboarding_completed_at', profile.onboarding_completed_at,
      'account_status', profile.account_status,
      'created_at', profile.created_at,
      'updated_at', profile.updated_at,
      'email', profile.email,
      'date_of_birth', profile.date_of_birth,
      'public_photo_object_key', profile.public_photo_object_key,
      'public_photo_consent', profile.public_photo_consent,
      'public_photo_updated_at', profile.public_photo_updated_at
    ) as profile
    from public.profiles profile
    join caller on caller.user_id = profile.id
  ),
  active_assignments as (
    select
      assignment.id,
      assignment.role_id,
      assignment.team_id,
      assignment.season_id,
      assignment.status,
      assignment.starts_at,
      assignment.ends_at,
      assignment.reason,
      assignment.created_at
    from public.user_role_assignments assignment
    join caller on caller.user_id = assignment.user_id
    join public.roles active_role on active_role.id = assignment.role_id and active_role.is_active
    left join public.member_compliance compliance on compliance.user_id = assignment.user_id
    where assignment.status = 'active'
      and assignment.revoked_at is null
      and (active_role.key <> 'canteen_staff' or compliance.volunteer_status = 'approved')
      and assignment.starts_at <= now()
      and (assignment.ends_at is null or assignment.ends_at > now())
  ),
  assignment_data as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', assignment.id,
          'status', assignment.status,
          'starts_at', assignment.starts_at,
          'ends_at', assignment.ends_at,
          'reason', assignment.reason,
          'role', jsonb_build_object(
            'id', role.id,
            'key', role.key,
            'name', role.name,
            'description', role.description,
            'is_sensitive', role.is_sensitive
          ),
          'team', case when team.id is null then null else jsonb_build_object(
            'id', team.id,
            'name', team.name
          ) end,
          'season', case when season.id is null then null else jsonb_build_object(
            'id', season.id,
            'name', season.name
          ) end
        )
        order by assignment.created_at desc
      ),
      '[]'::jsonb
    ) as assignments
    from active_assignments assignment
    join public.roles role on role.id = assignment.role_id
    left join public.teams team on team.id = assignment.team_id
    left join public.seasons season on season.id = assignment.season_id
  ),
  permission_data as (
    select coalesce(
      array_agg(distinct permission.key order by permission.key),
      array[]::text[]
    ) as permission_keys
    from active_assignments assignment
    join public.role_permissions role_permission
      on role_permission.role_id = assignment.role_id
    join public.permissions permission
      on permission.id = role_permission.permission_id and permission.is_active
  ),
  notification_data as (
    select count(*)::integer as unread_count
    from public.notifications notification
    join caller on caller.user_id = notification.recipient_id
    where notification.read_at is null
  ),
  child_data as (
    select
      exists (
        select 1
        from public.managed_child_accounts child
        join caller on caller.user_id = child.child_user_id
      ) as is_child_account,
      coalesce((
        select child.login_disabled
        from public.managed_child_accounts child
        join caller on caller.user_id = child.child_user_id
        limit 1
      ), false) as login_disabled
  )
  select case
    when caller.user_id is null then null
    else jsonb_build_object(
      'user_id', caller.user_id,
      'profile', profile_data.profile,
      'role_assignments', assignment_data.assignments,
      'permission_keys', to_jsonb(permission_data.permission_keys),
      'is_super_admin', '*' = any(permission_data.permission_keys),
      'unread_notifications', notification_data.unread_count,
      'is_child_account', child_data.is_child_account,
      'child_login_disabled', child_data.login_disabled
    )
  end
  from caller
  left join profile_data on true
  cross join assignment_data
  cross join permission_data
  cross join notification_data
  cross join child_data;
$$;

create or replace function app_private.update_canteen_order_state(
  target_order_id uuid,
  target_order_status text default null,
  target_payment_status text default null,
  change_reason text default null
)
returns table (
  order_id uuid,
  order_number text,
  old_order_status text,
  new_order_status text,
  old_payment_status text,
  new_payment_status text,
  customer_id uuid,
  recipient_id uuid,
  issued_vouchers int
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  order_row public.canteen_orders%rowtype;
  next_order_status text;
  next_payment_status text;
  issued_count int := 0;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not (app_private.has_permission('canteen.orders.manage') or app_private.has_permission('canteen.orders.fulfil')) then
    raise exception 'Worker not authorised';
  end if;

  select *
  into order_row
  from public.canteen_orders
  where id = target_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if not app_private.has_permission('canteen.orders.manage') and (target_payment_status is not null or target_order_status in ('cancelled','refunded','partially_refunded','expired')) then
    raise exception 'Canteen Staff can fulfil orders but cannot change payments, cancel, or refund';
  end if;

  next_order_status := coalesce(target_order_status, order_row.order_status);
  next_payment_status := coalesce(target_payment_status, order_row.payment_status);

  if next_order_status not in ('accepted','preparing','ready_for_pickup','collected','cancelled','refunded','partially_refunded','expired') then
    raise exception 'Invalid order status';
  end if;

  if next_payment_status not in ('unpaid','awaiting_payment','paid','partially_refunded','refunded') then
    raise exception 'Invalid payment status';
  end if;

  if order_row.order_status in ('collected','cancelled','refunded','expired') and next_order_status <> order_row.order_status then
    raise exception 'Closed orders cannot be moved';
  end if;

  if order_row.order_status = 'accepted' and next_order_status not in ('accepted','preparing','ready_for_pickup','cancelled') then
    raise exception 'Invalid status transition';
  end if;

  if order_row.order_status = 'preparing' and next_order_status not in ('preparing','ready_for_pickup','cancelled') then
    raise exception 'Invalid status transition';
  end if;

  if order_row.order_status = 'ready_for_pickup' and next_order_status not in ('ready_for_pickup','collected') then
    raise exception 'Invalid status transition';
  end if;

  update public.canteen_orders
  set order_status = next_order_status,
      payment_status = next_payment_status,
      pickup_code = coalesce(pickup_code, 'GEORDER:' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))),
      updated_at = now()
  where id = target_order_id;

  insert into public.order_status_history (order_id, old_status, new_status, changed_by, reason)
  values (target_order_id, order_row.order_status, next_order_status, auth.uid(), change_reason);

  if next_payment_status = 'paid' then
    issued_count := app_private.issue_canteen_order_vouchers(target_order_id);
  end if;

  return query
  select target_order_id, order_row.order_number, order_row.order_status, next_order_status,
         order_row.payment_status, next_payment_status, order_row.customer_id, order_row.recipient_id, issued_count;
end;
$$;

drop policy if exists orders_read_own_or_staff on public.canteen_orders;
create policy orders_read_own_or_staff on public.canteen_orders for select to authenticated using(customer_id=auth.uid() or recipient_id=auth.uid() or app_private.has_permission('canteen.orders.view') or app_private.has_permission('canteen.orders.manage'));
drop policy if exists orders_items_read_own_or_staff on public.canteen_order_items;
create policy orders_items_read_own_or_staff on public.canteen_order_items for select to authenticated using(exists(select 1 from public.canteen_orders o where o.id=order_id and(o.customer_id=auth.uid() or o.recipient_id=auth.uid())) or app_private.has_permission('canteen.orders.view') or app_private.has_permission('canteen.orders.manage'));
drop policy if exists order_history_staff_read on public.order_status_history;
create policy order_history_staff_read on public.order_status_history for select to authenticated using(app_private.has_permission('canteen.orders.view') or app_private.has_permission('canteen.orders.manage'));
revoke insert,update,delete on public.user_role_assignments from authenticated;
revoke all on function public.assign_user_role(uuid,uuid,uuid,uuid,timestamptz,timestamptz,text) from public,anon;
grant execute on function public.assign_user_role(uuid,uuid,uuid,uuid,timestamptz,timestamptz,text) to authenticated,service_role;
revoke all on function public.revoke_user_role(uuid,text) from public,anon;
grant execute on function public.revoke_user_role(uuid,text) to authenticated,service_role;
revoke execute on function public.request_role(uuid,uuid,uuid,text,text,text) from public,anon,authenticated;
revoke execute on function public.withdraw_role_request(uuid,text) from public,anon,authenticated;
revoke execute on function public.review_role_request(uuid,text,text,timestamptz,timestamptz) from public,anon,authenticated;
revoke execute on function public.request_team_access(uuid,text,text) from public,anon,authenticated;
revoke execute on function public.review_team_access_request(uuid,text,text) from public,anon,authenticated;

-- Rollback notes: role records and assignment history are never deleted. Restore prior mappings and
-- function definitions if required; retain member_compliance until sensitive data is securely migrated.