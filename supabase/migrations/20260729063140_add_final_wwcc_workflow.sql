-- Final forward-only WWCC workflow. Supporting files remain optional and private.

-- Replace the active volunteer roster workflow with auditable WWCC submissions.
-- Legacy opportunity, shift and assignment tables are intentionally retained for
-- a later controlled data-retention review, but are no longer used by the app.

insert into public.roles(
  key,name,description,is_system,is_sensitive,may_request,
  requires_team_scope,requires_season_scope,requires_super_admin_approval,
  sort_order,is_active,role_kind
)
values (
  'volunteer','Volunteer',
  'Club-assigned volunteer access that activates after WWCC approval.',
  true,true,false,false,false,false,35,true,'global'
)
on conflict(key) do update set
  name=excluded.name,
  description=excluded.description,
  is_system=true,
  is_sensitive=true,
  may_request=false,
  requires_team_scope=false,
  requires_season_scope=false,
  requires_super_admin_approval=false,
  sort_order=excluded.sort_order,
  is_active=true,
  role_kind='global';

create table if not exists public.wwcc_submissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  role_assignment_id uuid references public.user_role_assignments(id) on delete set null,
  legal_name text not null check (char_length(trim(legal_name)) between 2 and 160),
  wwcc_number text not null check (char_length(wwcc_number) between 5 and 80),
  expiry_date date not null,
  date_of_birth date not null,
  clearance_type text not null check (clearance_type in ('volunteer','paid_worker')),
  notes text check (notes is null or char_length(notes) <= 1000),
  document_file_id uuid references public.file_records(id) on delete restrict,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected','resubmission_required')),
  submitted_at timestamptz not null default now(),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  review_reason text check (review_reason is null or char_length(review_reason) <= 1000),
  verification_outcome text,
  verified_wwcc_number text,
  verified_expiry_date date,
  verified_clearance_type text check (verified_clearance_type is null or verified_clearance_type in ('volunteer','paid_worker')),
  supersedes_submission_id uuid references public.wwcc_submissions(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (status='pending' and reviewed_by is null and reviewed_at is null)
    or
    (status<>'pending' and reviewed_by is not null and reviewed_at is not null)
  )
);

alter table public.wwcc_submissions enable row level security;

do $$ begin
 if exists(select 1 from public.wwcc_submissions where status='pending' group by user_id having count(*)>1) then raise exception 'Duplicate pending WWCC submissions exist'; end if;
 if exists(select 1 from public.user_role_assignments a join public.roles r on r.id=a.role_id and r.key='volunteer' where a.revoked_at is null and a.status in ('pending','active','suspended','expired') group by a.user_id,a.role_id having count(*)>1) then raise exception 'Duplicate current volunteer assignments exist'; end if;
end $$;

create unique index if not exists wwcc_submissions_one_pending_per_user
  on public.wwcc_submissions(user_id) where status='pending';

create index if not exists wwcc_submissions_user_history_idx
  on public.wwcc_submissions(user_id,submitted_at desc);

create index if not exists wwcc_submissions_review_queue_idx
  on public.wwcc_submissions(status,submitted_at);

create index if not exists wwcc_submissions_expiry_idx
  on public.wwcc_submissions(expiry_date) where status='approved';


create or replace function app_private.enforce_one_current_volunteer()
returns trigger language plpgsql security definer set search_path='' as $guard$
begin
  if exists(select 1 from public.roles r where r.id=new.role_id and r.key='volunteer')
     and new.revoked_at is null and new.status in ('pending','active','suspended','expired') then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.user_id::text,0));
    if exists(select 1 from public.user_role_assignments a where a.user_id=new.user_id and a.role_id=new.role_id
      and a.id<>new.id and a.revoked_at is null and a.status in ('pending','active','suspended','expired')) then
      raise exception 'A current volunteer assignment already exists';
    end if;
  end if;
  return new;
end $guard$;
revoke all on function app_private.enforce_one_current_volunteer() from public,anon,authenticated;
grant execute on function app_private.enforce_one_current_volunteer() to service_role;
drop trigger if exists user_role_assignments_one_current_volunteer on public.user_role_assignments;
create trigger user_role_assignments_one_current_volunteer before insert or update on public.user_role_assignments
for each row execute function app_private.enforce_one_current_volunteer();

drop trigger if exists wwcc_submissions_set_updated_at on public.wwcc_submissions;

create trigger wwcc_submissions_set_updated_at
before update on public.wwcc_submissions
for each row execute function app_private.set_updated_at();

revoke all on public.wwcc_submissions from anon,authenticated;

grant select,insert on public.wwcc_submissions to authenticated;

grant select,insert,update,delete on public.wwcc_submissions to service_role;

drop policy if exists wwcc_submissions_read on public.wwcc_submissions;

create policy wwcc_submissions_read
on public.wwcc_submissions for select to authenticated
using (
  user_id=(select auth.uid())
  or app_private.has_permission('volunteers.view')
  or app_private.has_permission('wwcc.view')
  or app_private.has_permission('wwcc.verify')
);

drop policy if exists wwcc_submissions_insert_own on public.wwcc_submissions;

create policy wwcc_submissions_insert_own on public.wwcc_submissions for insert to authenticated with check (
  user_id=(select auth.uid()) and status='pending' and reviewed_by is null and reviewed_at is null
  and clearance_type in ('volunteer','paid_worker')
  and exists(select 1 from public.user_role_assignments a join public.roles r on r.id=a.role_id
    where a.id=role_assignment_id and a.user_id=(select auth.uid()) and a.revoked_at is null and r.key='volunteer')
  and (document_file_id is null or exists(select 1 from public.file_records f where f.id=document_file_id
    and f.owner_id=(select auth.uid()) and f.visibility='private' and f.related_entity_type='wwcc_submission' and f.related_entity_id=id))
);

create or replace function public.request_volunteer_role()
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid=(select auth.uid()); volunteer_role_id uuid; assignment_id uuid; dob date;
begin
  if actor is not null then perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(actor::text,0)); end if;
  if actor is null then raise exception 'You must be signed in'; end if;
  if exists(select 1 from public.managed_child_accounts where child_user_id=actor) then
    raise exception 'Child accounts cannot request volunteer access';
  end if;
  select date_of_birth into dob from public.profiles where id=actor;
  if dob is null or dob > current_date - interval '18 years' then
    raise exception 'Volunteer requests require an adult account with a date of birth';
  end if;
  select id into volunteer_role_id from public.roles where key='volunteer' and is_active;
  select id into assignment_id from public.user_role_assignments
   where user_id=actor and role_id=volunteer_role_id and revoked_at is null
   order by created_at desc limit 1;
  if assignment_id is null then
    insert into public.user_role_assignments(user_id,role_id,status,reason,starts_at)
    values(actor,volunteer_role_id,'pending','Member requested volunteer role; WWCC review required',now()) returning id into assignment_id;
  end if;
  insert into public.member_compliance(user_id,volunteer_status,wwcc_status)
    values(actor,'pending','not_supplied') on conflict(user_id) do nothing;
  perform app_private.write_audit_log('volunteer.requested','user_role_assignment',assignment_id,null,
    jsonb_build_object('user_id',actor,'status','pending'),'Member volunteer request');
  return assignment_id;
end $$;

revoke all on function public.request_volunteer_role() from public,anon;

grant execute on function public.request_volunteer_role() to authenticated,service_role;

create or replace function public.review_wwcc_submission(
  submission_id uuid,
  decision text,
  decision_reason text,
  corrected_expiry_date date default null,
  corrected_wwcc_number text default null
)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  actor uuid:=(select auth.uid());
  before_row public.wwcc_submissions%rowtype;
  final_expiry date;
  final_number text;
  assignment_status text;
begin
  if actor is null or not app_private.has_permission('wwcc.verify') then
    raise exception 'Not authorised';
  end if;
  if decision not in ('approved','rejected','resubmission_required') then
    raise exception 'Invalid WWCC decision';
  end if;
  if coalesce(length(trim(decision_reason)),0)<5 then
    raise exception 'A review reason is required';
  end if;

  select * into before_row
  from public.wwcc_submissions
  where id=submission_id and status in ('pending','approved')
  for update;
  if not found then raise exception 'Reviewable WWCC submission not found'; end if;
  if before_row.status='approved' and decision<>'approved' then
    raise exception 'An approved WWCC can only have its verified details updated';
  end if;
  if before_row.user_id=actor then raise exception 'You cannot approve your own WWCC'; end if;

  final_expiry:=coalesce(corrected_expiry_date,before_row.expiry_date);
  final_number:=upper(regexp_replace(
    trim(coalesce(corrected_wwcc_number,before_row.wwcc_number)),'\s+','','g'
  ));
  if decision='approved' and final_expiry<current_date then
    raise exception 'An expired WWCC cannot be approved';
  end if;

  update public.wwcc_submissions set
    status=decision,
    expiry_date=final_expiry,
    wwcc_number=final_number,
    reviewed_by=actor,
    reviewed_at=now(),
    review_reason=trim(decision_reason),
    verification_outcome=decision,
    verified_wwcc_number=final_number,
    verified_expiry_date=final_expiry,
    verified_clearance_type=before_row.clearance_type
  where id=submission_id;

  assignment_status:=case when decision='approved' then 'active' else 'pending' end;

  update public.member_compliance set
    volunteer_status=case when decision='approved' then 'approved' else 'rejected' end,
    volunteer_approved_at=case when decision='approved' then now() else volunteer_approved_at end,
    volunteer_approved_by=case when decision='approved' then actor else volunteer_approved_by end,
    volunteer_reason=trim(decision_reason),
    wwcc_number=final_number,
    wwcc_status=case when decision='approved' then 'verified' else 'rejected' end,
    wwcc_expiry_date=final_expiry,
    wwcc_verified_at=case when decision='approved' then now() else wwcc_verified_at end,
    wwcc_verified_by=case when decision='approved' then actor else wwcc_verified_by end,
    wwcc_verification_name=before_row.legal_name,
    updated_at=now()
  where user_id=before_row.user_id;

  update public.user_role_assignments assignment set
    status=assignment_status,
    updated_at=now()
  from public.roles role
  where assignment.user_id=before_row.user_id
    and assignment.role_id=role.id
    and role.key='volunteer'
    and assignment.revoked_at is null
    and assignment.status in ('pending','active','suspended','expired');

  insert into public.notifications(
    recipient_id,title,body,category,action_url,dedupe_key,
    related_entity_type,related_entity_id
  )
  values (
    before_row.user_id,
    case
      when decision='approved' then 'WWCC approved'
      when decision='rejected' then 'WWCC submission rejected'
      else 'WWCC resubmission required'
    end,
    trim(decision_reason),
    'roles','/portal/roles/#wwcc',
    'wwcc-reviewed:'||submission_id||':'||decision,
    'wwcc_submission',submission_id
  )
  on conflict(recipient_id,dedupe_key) where dedupe_key is not null do nothing;

  perform app_private.write_audit_log(
    'wwcc_submission.'||decision,'wwcc_submission',submission_id,
    jsonb_build_object(
      'status',before_row.status,
      'expiry_date',before_row.expiry_date,
      'wwcc_last4',right(before_row.wwcc_number,4)
    ),
    jsonb_build_object(
      'status',decision,
      'expiry_date',final_expiry,
      'wwcc_last4',right(final_number,4),
      'reviewed_by',actor
    ),
    trim(decision_reason)
  );
end;
$$;

revoke all on function public.review_wwcc_submission(uuid,text,text,date,text)
  from public,anon;

grant execute on function public.review_wwcc_submission(uuid,text,text,date,text)
  to authenticated,service_role;

create or replace function public.refresh_wwcc_status(target_user_id uuid default null)
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare
  actor uuid:=(select auth.uid());
  scoped_user uuid:=target_user_id;
  changed_count integer:=0;
begin
  if actor is null then raise exception 'You must be signed in'; end if;
  if scoped_user is null and not (
    app_private.has_permission('wwcc.verify')
    or app_private.has_permission('volunteers.view')
  ) then
    scoped_user:=actor;
  end if;
  if scoped_user is not null and scoped_user<>actor and not (
    app_private.has_permission('wwcc.verify')
    or app_private.has_permission('volunteers.view')
  ) then
    raise exception 'Not authorised';
  end if;

  with expired as (
    update public.member_compliance compliance set
      volunteer_status='expired',
      volunteer_reason='WWCC expired on '||compliance.wwcc_expiry_date,
      wwcc_status='expired',
      updated_at=now()
    where compliance.wwcc_status='verified'
      and compliance.wwcc_expiry_date<current_date
      and (scoped_user is null or compliance.user_id=scoped_user)
    returning compliance.user_id,compliance.wwcc_expiry_date
  ),
  expired_roles as (
    update public.user_role_assignments assignment set
      status='expired',updated_at=now()
    from public.roles role, expired
    where assignment.user_id=expired.user_id
      and assignment.role_id=role.id
      and role.key='volunteer'
      and assignment.revoked_at is null
      and assignment.status='active'
    returning assignment.user_id
  )
  select count(*) into changed_count from expired;

  insert into public.notifications(
    recipient_id,title,body,category,action_url,dedupe_key,
    related_entity_type,related_entity_id
  )
  select
    compliance.user_id,'WWCC expiring soon',
    'Your Working With Children Check expires on '||
      to_char(compliance.wwcc_expiry_date,'DD Mon YYYY')||'. Submit the renewed check.',
    'roles','/portal/roles/#wwcc',
    'wwcc-expiring:'||compliance.user_id||':'||compliance.wwcc_expiry_date,
    'member_compliance',compliance.user_id
  from public.member_compliance compliance
  where compliance.wwcc_status='verified'
    and compliance.wwcc_expiry_date between current_date and (current_date+interval '3 months')::date
    and (scoped_user is null or compliance.user_id=scoped_user)
  on conflict(recipient_id,dedupe_key) where dedupe_key is not null do nothing;

  insert into public.notifications(
    recipient_id,title,body,category,action_url,dedupe_key,
    related_entity_type,related_entity_id
  )
  select
    compliance.user_id,'WWCC expired',
    'Your Working With Children Check has expired. Submit the renewed check to reactivate your volunteer role.',
    'roles','/portal/roles/#wwcc',
    'wwcc-expired:'||compliance.user_id||':'||compliance.wwcc_expiry_date,
    'member_compliance',compliance.user_id
  from public.member_compliance compliance
  where compliance.wwcc_status='expired'
    and (scoped_user is null or compliance.user_id=scoped_user)
  on conflict(recipient_id,dedupe_key) where dedupe_key is not null do nothing;

  return changed_count;
end;
$$;

revoke all on function public.refresh_wwcc_status(uuid) from public,anon;

grant execute on function public.refresh_wwcc_status(uuid) to authenticated,service_role;
