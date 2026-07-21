-- Secure portal/admin phase: request workflow fields, safe role-management RPCs,
-- searchable profile email, and admin reporting helpers.

alter table public.profiles
  add column if not exists email text;

create unique index if not exists profiles_email_lower_idx
  on public.profiles (lower(email))
  where email is not null and email <> '';

update public.profiles p
set email = u.email
from auth.users u
where u.id = p.id
  and p.email is null;

alter table public.roles
  add column if not exists may_request boolean not null default false,
  add column if not exists requires_team_scope boolean not null default false,
  add column if not exists requires_season_scope boolean not null default false,
  add column if not exists requires_super_admin_approval boolean not null default false,
  add column if not exists sort_order int not null default 100;

update public.roles
set
  may_request = key in (
    'club_member',
    'parent_guardian',
    'player',
    'coach',
    'assistant_coach',
    'team_manager',
    'canteen_worker',
    'content_editor',
    'volunteer_coordinator'
  ),
  requires_team_scope = key in ('coach', 'assistant_coach', 'team_manager'),
  requires_season_scope = key in ('player', 'coach', 'assistant_coach', 'team_manager'),
  requires_super_admin_approval = key in (
    'super_administrator',
    'club_administrator',
    'treasurer',
    'registrar',
    'canteen_manager',
    'merchandise_manager'
  ),
  sort_order = case key
    when 'general_user' then 10
    when 'club_member' then 20
    when 'parent_guardian' then 30
    when 'player' then 40
    when 'coach' then 50
    when 'assistant_coach' then 60
    when 'team_manager' then 70
    when 'canteen_worker' then 80
    when 'content_editor' then 90
    when 'volunteer_coordinator' then 100
    when 'club_administrator' then 900
    when 'super_administrator' then 1000
    else 500
  end;

alter table public.role_requests
  add column if not exists reason text,
  add column if not exists experience text,
  add column if not exists notes text,
  add column if not exists decision_reason text,
  add column if not exists withdrawn_at timestamptz,
  add column if not exists submitted_at timestamptz;

update public.role_requests
set
  status = case status
    when 'pending' then 'submitted'
    else status
  end,
  submitted_at = coalesce(submitted_at, created_at),
  reason = coalesce(reason, relationship_note)
where status in ('pending', 'approved', 'rejected', 'cancelled');

alter table public.role_requests
  alter column status set default 'submitted';

alter table public.role_requests
  drop constraint if exists role_requests_status_check;

alter table public.role_requests
  add constraint role_requests_status_check
  check (status in ('draft','submitted','under_review','approved','rejected','withdrawn','cancelled'));

create index if not exists profiles_full_name_idx on public.profiles using gin (to_tsvector('simple', coalesce(full_name, '') || ' ' || coalesce(preferred_name, '') || ' ' || coalesce(email, '') || ' ' || coalesce(mobile, '')));
create index if not exists role_requests_status_created_idx on public.role_requests (status, created_at desc);
create index if not exists role_requests_requester_status_idx on public.role_requests (requester_id, status, created_at desc);
create index if not exists user_role_assignments_role_status_idx on public.user_role_assignments (role_id, status, starts_at, ends_at);

create or replace function app_private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
begin
  insert into public.profiles (id, full_name, email, terms_accepted_at, privacy_accepted_at)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.email,
    case when coalesce(new.raw_user_meta_data ->> 'terms_accepted', 'false') = 'true' then now() else null end,
    case when coalesce(new.raw_user_meta_data ->> 'privacy_accepted', 'false') = 'true' then now() else null end
  )
  on conflict (id) do update
  set email = excluded.email,
      full_name = case when public.profiles.full_name = '' then excluded.full_name else public.profiles.full_name end;

  insert into public.user_role_assignments (user_id, role_id, status, reason)
  select new.id, r.id, 'active', 'Automatic general-user provisioning'
  from public.roles r
  where r.key = 'general_user'
    and not exists (
      select 1
      from public.user_role_assignments ura
      where ura.user_id = new.id
        and ura.role_id = r.id
        and ura.status = 'active'
    );

  return new;
end;
$$;

create or replace function public.request_role(
  requested_role_id uuid,
  target_team_id uuid default null,
  target_season_id uuid default null,
  request_reason text default null,
  request_experience text default null,
  request_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  request_id uuid;
  target_role public.roles%rowtype;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to request club access';
  end if;

  select * into target_role
  from public.roles
  where id = requested_role_id
    and is_system
    and may_request
    and key <> 'super_administrator';

  if not found then
    raise exception 'This role is not available for portal requests';
  end if;

  if target_role.requires_team_scope and target_team_id is null then
    raise exception 'Select a team for this role request';
  end if;

  if target_role.requires_season_scope and target_season_id is null then
    raise exception 'Select a season for this role request';
  end if;

  if coalesce(length(trim(request_reason)), 0) < 10 then
    raise exception 'Tell us a little more about the access you need';
  end if;

  if exists (
    select 1
    from public.role_requests rr
    where rr.requester_id = auth.uid()
      and rr.requested_role_id = requested_role_id
      and rr.status in ('draft','submitted','under_review')
      and rr.team_id is not distinct from target_team_id
      and rr.season_id is not distinct from target_season_id
  ) then
    raise exception 'You already have an open request for this role and scope';
  end if;

  insert into public.role_requests (
    requester_id,
    requested_role_id,
    team_id,
    season_id,
    reason,
    experience,
    notes,
    relationship_note,
    status,
    submitted_at
  )
  values (
    auth.uid(),
    requested_role_id,
    target_team_id,
    target_season_id,
    trim(request_reason),
    nullif(trim(coalesce(request_experience, '')), ''),
    nullif(trim(coalesce(request_notes, '')), ''),
    trim(request_reason),
    'submitted',
    now()
  )
  returning id into request_id;

  perform app_private.write_audit_log(
    'role_request.submitted',
    'role_request',
    request_id,
    null,
    jsonb_build_object('requester_id', auth.uid(), 'role_id', requested_role_id, 'team_id', target_team_id, 'season_id', target_season_id),
    trim(request_reason)
  );

  return request_id;
end;
$$;

create or replace function public.withdraw_role_request(target_request_id uuid, withdrawal_reason text default null)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  before_row jsonb;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in';
  end if;

  select to_jsonb(rr) into before_row
  from public.role_requests rr
  where rr.id = target_request_id
    and rr.requester_id = auth.uid()
    and rr.status in ('draft','submitted','under_review');

  if before_row is null then
    raise exception 'This request cannot be withdrawn';
  end if;

  update public.role_requests
  set status = 'withdrawn',
      withdrawn_at = now(),
      decision_reason = nullif(trim(coalesce(withdrawal_reason, '')), ''),
      updated_at = now()
  where id = target_request_id;

  perform app_private.write_audit_log('role_request.withdrawn', 'role_request', target_request_id, before_row, null, withdrawal_reason);
end;
$$;

create or replace function public.assign_user_role(
  target_user_id uuid,
  target_role_id uuid,
  target_team_id uuid default null,
  target_season_id uuid default null,
  starts_at timestamptz default now(),
  ends_at timestamptz default null,
  assignment_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  assignment_id uuid;
  target_role public.roles%rowtype;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in';
  end if;

  if auth.uid() = target_user_id and not app_private.has_permission('*') then
    raise exception 'You cannot change your own role access from the portal';
  end if;

  if not app_private.can_assign_role(target_role_id) then
    raise exception 'You do not have permission to assign this role';
  end if;

  select * into target_role from public.roles where id = target_role_id and is_system;
  if not found then
    raise exception 'Role not found';
  end if;

  if target_role.key = 'super_administrator' and not app_private.has_permission('*') then
    raise exception 'Only a super administrator can assign super administrator access';
  end if;

  if target_role.requires_team_scope and target_team_id is null then
    raise exception 'Select a team for this role';
  end if;

  if target_role.requires_season_scope and target_season_id is null then
    raise exception 'Select a season for this role';
  end if;

  if ends_at is not null and ends_at <= starts_at then
    raise exception 'Expiry must be after the start date';
  end if;

  if coalesce(length(trim(assignment_reason)), 0) < 10 then
    raise exception 'A clear assignment reason is required';
  end if;

  if exists (
    select 1
    from public.user_role_assignments ura
    where ura.user_id = target_user_id
      and ura.role_id = target_role_id
      and ura.status = 'active'
      and ura.revoked_at is null
      and ura.team_id is not distinct from target_team_id
      and ura.season_id is not distinct from target_season_id
      and ura.starts_at <= now()
      and (ura.ends_at is null or ura.ends_at > now())
  ) then
    raise exception 'This user already has an active matching assignment';
  end if;

  insert into public.user_role_assignments (
    user_id,
    role_id,
    team_id,
    season_id,
    starts_at,
    ends_at,
    status,
    reason,
    assigned_by
  )
  values (
    target_user_id,
    target_role_id,
    target_team_id,
    target_season_id,
    coalesce(starts_at, now()),
    ends_at,
    'active',
    trim(assignment_reason),
    auth.uid()
  )
  returning id into assignment_id;

  perform app_private.write_audit_log(
    'role_assignment.created',
    'user_role_assignment',
    assignment_id,
    null,
    jsonb_build_object('user_id', target_user_id, 'role_id', target_role_id, 'team_id', target_team_id, 'season_id', target_season_id),
    trim(assignment_reason)
  );

  return assignment_id;
end;
$$;

create or replace function public.revoke_user_role(target_assignment_id uuid, revocation_reason text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  before_row public.user_role_assignments%rowtype;
  role_key text;
  remaining_super_admins int;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in';
  end if;

  select ura.*
  into before_row
  from public.user_role_assignments ura
  join public.roles r on r.id = ura.role_id
  where ura.id = target_assignment_id
    and ura.status = 'active';

  if before_row.id is null then
    raise exception 'Active role assignment not found';
  end if;

  select key into role_key
  from public.roles
  where id = before_row.role_id;

  if not app_private.can_assign_role(before_row.role_id) then
    raise exception 'You do not have permission to revoke this role';
  end if;

  if before_row.user_id = auth.uid() and not app_private.has_permission('*') then
    raise exception 'You cannot revoke your own administration access';
  end if;

  if coalesce(length(trim(revocation_reason)), 0) < 10 then
    raise exception 'A clear revocation reason is required';
  end if;

  if role_key = 'super_administrator' then
    select count(*) into remaining_super_admins
    from public.user_role_assignments ura
    join public.roles r on r.id = ura.role_id
    where r.key = 'super_administrator'
      and ura.status = 'active'
      and ura.revoked_at is null
      and ura.starts_at <= now()
      and (ura.ends_at is null or ura.ends_at > now())
      and ura.id <> target_assignment_id;

    if remaining_super_admins < 1 then
      raise exception 'Cannot remove the final active super administrator';
    end if;
  end if;

  update public.user_role_assignments
  set status = 'revoked',
      revoked_by = auth.uid(),
      revoked_at = now(),
      reason = trim(revocation_reason),
      updated_at = now()
  where id = target_assignment_id;

  perform app_private.write_audit_log('role_assignment.revoked', 'user_role_assignment', target_assignment_id, to_jsonb(before_row), null, trim(revocation_reason));
end;
$$;

create or replace function public.review_role_request(
  target_request_id uuid,
  decision text,
  review_reason text,
  assignment_starts_at timestamptz default now(),
  assignment_ends_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  req public.role_requests%rowtype;
  assignment_id uuid;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in';
  end if;

  if decision not in ('approved', 'rejected', 'under_review') then
    raise exception 'Invalid review decision';
  end if;

  if not app_private.has_permission('roles.review') then
    raise exception 'You do not have permission to review role requests';
  end if;

  if coalesce(length(trim(review_reason)), 0) < 10 then
    raise exception 'A clear review note is required';
  end if;

  select * into req
  from public.role_requests
  where id = target_request_id
    and status in ('submitted','under_review')
  for update;

  if req.id is null then
    raise exception 'Open role request not found';
  end if;

  if req.requester_id = auth.uid() then
    raise exception 'You cannot review your own role request';
  end if;

  if decision = 'under_review' then
    update public.role_requests
    set status = 'under_review',
        reviewed_by = auth.uid(),
        review_note = trim(review_reason),
        updated_at = now()
    where id = target_request_id;
    perform app_private.write_audit_log('role_request.under_review', 'role_request', target_request_id, to_jsonb(req), null, trim(review_reason));
    return null;
  end if;

  if decision = 'approved' then
    assignment_id := public.assign_user_role(
      req.requester_id,
      req.requested_role_id,
      req.team_id,
      req.season_id,
      assignment_starts_at,
      assignment_ends_at,
      trim(review_reason)
    );
  end if;

  update public.role_requests
  set status = decision,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      review_note = trim(review_reason),
      decision_reason = trim(review_reason),
      updated_at = now()
  where id = target_request_id;

  perform app_private.write_audit_log('role_request.' || decision, 'role_request', target_request_id, to_jsonb(req), jsonb_build_object('assignment_id', assignment_id), trim(review_reason));

  return assignment_id;
end;
$$;

create or replace function public.admin_dashboard_summary()
returns jsonb
language sql
stable
security definer
set search_path = public, extensions
as $$
  select case
    when not (
      app_private.has_permission('users.read')
      or app_private.has_permission('roles.read')
      or app_private.has_permission('roles.review')
      or app_private.has_permission('audit.read')
    ) then '{}'::jsonb
    else jsonb_build_object(
      'total_profiles', (select count(*) from public.profiles),
      'recent_signups', (select count(*) from public.profiles where created_at >= now() - interval '30 days'),
      'pending_role_requests', (select count(*) from public.role_requests where status in ('submitted','under_review')),
      'active_role_assignments', (select count(*) from public.user_role_assignments where status = 'active' and starts_at <= now() and (ends_at is null or ends_at > now())),
      'expired_assignments', (select count(*) from public.user_role_assignments where status = 'active' and ends_at is not null and ends_at <= now()),
      'expiring_soon', (select count(*) from public.user_role_assignments where status = 'active' and ends_at between now() and now() + interval '30 days'),
      'users_with_multiple_roles', (
        select count(*) from (
          select user_id
          from public.user_role_assignments
          where status = 'active' and starts_at <= now() and (ends_at is null or ends_at > now())
          group by user_id
          having count(*) > 1
        ) multi
      ),
      'incomplete_profiles', (select count(*) from public.profiles where onboarding_completed_at is null),
      'recent_admin_actions', (select count(*) from public.audit_logs where created_at >= now() - interval '7 days')
    )
  end;
$$;

create or replace view public.role_catalog
with (security_invoker = true)
as
select
  r.id,
  r.key,
  r.name,
  r.description,
  r.is_system,
  r.is_sensitive,
  r.may_request,
  r.requires_team_scope,
  r.requires_season_scope,
  r.requires_super_admin_approval,
  r.sort_order,
  coalesce(
    jsonb_agg(
      jsonb_build_object('key', p.key, 'name', p.name, 'description', p.description)
      order by p.key
    ) filter (where p.id is not null),
    '[]'::jsonb
  ) as permissions
from public.roles r
left join public.role_permissions rp on rp.role_id = r.id
left join public.permissions p on p.id = rp.permission_id
group by r.id;

grant select on public.role_catalog to authenticated;
grant execute on function public.request_role(uuid, uuid, uuid, text, text, text) to authenticated;
grant execute on function public.withdraw_role_request(uuid, text) to authenticated;
grant execute on function public.assign_user_role(uuid, uuid, uuid, uuid, timestamptz, timestamptz, text) to authenticated;
grant execute on function public.revoke_user_role(uuid, text) to authenticated;
grant execute on function public.review_role_request(uuid, text, text, timestamptz, timestamptz) to authenticated;
grant execute on function public.admin_dashboard_summary() to authenticated;
