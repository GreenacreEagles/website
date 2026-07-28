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
  notes text check (notes is null or char_length(notes) <= 1000),
  document_file_id uuid not null references public.file_records(id) on delete restrict,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected','resubmission_required')),
  submitted_at timestamptz not null default now(),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  review_reason text check (review_reason is null or char_length(review_reason) <= 1000),
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

create unique index if not exists wwcc_submissions_one_pending_per_user
  on public.wwcc_submissions(user_id) where status='pending';
create index if not exists wwcc_submissions_user_history_idx
  on public.wwcc_submissions(user_id,submitted_at desc);
create index if not exists wwcc_submissions_review_queue_idx
  on public.wwcc_submissions(status,submitted_at);
create index if not exists wwcc_submissions_expiry_idx
  on public.wwcc_submissions(expiry_date) where status='approved';

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
create policy wwcc_submissions_insert_own
on public.wwcc_submissions for insert to authenticated
with check (
  user_id=(select auth.uid())
  and status='pending'
  and reviewed_by is null
  and reviewed_at is null
  and exists (
    select 1
    from public.user_role_assignments assignment
    join public.roles role on role.id=assignment.role_id
    where assignment.id=role_assignment_id
      and assignment.user_id=(select auth.uid())
      and assignment.revoked_at is null
      and assignment.status in ('pending','active','suspended','expired')
      and role.key='volunteer'
      and role.is_active
  )
  and exists (
    select 1 from public.file_records file
    where file.id=document_file_id
      and file.owner_id=(select auth.uid())
      and file.visibility='private'
      and file.related_entity_type='wwcc_submission'
      and file.related_entity_id=id
  )
);

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
set search_path=''
as $$
declare
  assignment_id uuid;
  target_role public.roles%rowtype;
  initial_status text;
begin
  if auth.uid() is null then raise exception 'You must be signed in'; end if;
  if auth.uid()=target_user_id and not app_private.has_permission('*') then
    raise exception 'You cannot change your own role access';
  end if;
  select * into target_role
  from public.roles
  where id=target_role_id and is_active and role_kind in ('global','technical');
  if not found then raise exception 'Supported global role not found'; end if;
  if target_role.key='general_user' then raise exception 'General User is assigned automatically'; end if;
  if target_team_id is not null or target_season_id is not null then
    raise exception 'Global roles cannot be scoped to a team or season';
  end if;
  if not app_private.can_assign_role(target_role_id) then
    raise exception 'You do not have permission to assign this role';
  end if;
  if ends_at is not null and ends_at<=starts_at then
    raise exception 'Expiry must be after the start date';
  end if;
  if coalesce(length(trim(assignment_reason)),0)<10 then
    raise exception 'A clear assignment reason is required';
  end if;

  initial_status:=case when target_role.key='volunteer' then 'pending' else 'active' end;
  insert into public.user_role_assignments(
    user_id,role_id,starts_at,ends_at,status,reason,assigned_by
  )
  values (
    target_user_id,target_role_id,coalesce(starts_at,now()),ends_at,
    initial_status,trim(assignment_reason),auth.uid()
  )
  returning id into assignment_id;

  if target_role.key='volunteer' then
    insert into public.member_compliance(user_id,volunteer_status,wwcc_status)
    values(target_user_id,'pending','not_supplied')
    on conflict(user_id) do update set
      volunteer_status='pending',
      wwcc_status=case
        when public.member_compliance.wwcc_status in ('verified','exempt')
          and (public.member_compliance.wwcc_expiry_date is null or public.member_compliance.wwcc_expiry_date>=current_date)
        then public.member_compliance.wwcc_status
        else 'not_supplied'
      end,
      updated_at=now();

    insert into public.notifications(
      recipient_id,title,body,category,action_url,dedupe_key,
      related_entity_type,related_entity_id
    )
    values (
      target_user_id,'WWCC information required',
      'Submit your Working With Children Check details and supporting document to activate your volunteer role.',
      'roles','/portal/roles/#wwcc',
      'wwcc-required:'||assignment_id,
      'user_role_assignment',assignment_id
    )
    on conflict(recipient_id,dedupe_key) where dedupe_key is not null do nothing;
  end if;

  perform app_private.write_audit_log(
    'role_assignment.created','user_role_assignment',assignment_id,null,
    jsonb_build_object(
      'user_id',target_user_id,
      'role_key',target_role.key,
      'status',initial_status
    ),
    trim(assignment_reason)
  );
  return assignment_id;
exception
  when unique_violation then
    raise exception 'This user already has a current global role assignment';
end;
$$;

revoke all on function public.assign_user_role(uuid,uuid,uuid,uuid,timestamptz,timestamptz,text)
  from public,anon;
grant execute on function public.assign_user_role(uuid,uuid,uuid,uuid,timestamptz,timestamptz,text)
  to authenticated,service_role;

drop index if exists public.user_role_assignments_one_current_volunteer;
create unique index user_role_assignments_one_current_volunteer
  on public.user_role_assignments(user_id,role_id)
  where revoked_at is null and status in ('pending','active','suspended','expired');

create or replace function public.submit_wwcc_submission(
  submission_id uuid,
  assignment_id uuid,
  legal_name text,
  wwcc_number text,
  expiry_date date,
  document_file_id uuid,
  submission_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  actor uuid:=(select auth.uid());
  previous_id uuid;
  saved_id uuid;
begin
  if actor is null then raise exception 'You must be signed in'; end if;
  if coalesce(length(trim(legal_name)),0)<2 then raise exception 'Legal name is required'; end if;
  if coalesce(length(regexp_replace(wwcc_number,'\s+','','g')),0)<5 then
    raise exception 'WWCC number is required';
  end if;
  if expiry_date<current_date then raise exception 'WWCC expiry date has passed'; end if;
  if exists(select 1 from public.wwcc_submissions where user_id=actor and status='pending') then
    raise exception 'A WWCC submission is already pending review';
  end if;
  if not exists (
    select 1
    from public.user_role_assignments assignment
    join public.roles role on role.id=assignment.role_id
    where assignment.id=assignment_id
      and assignment.user_id=actor
      and assignment.revoked_at is null
      and assignment.status in ('pending','active','suspended','expired')
      and role.key='volunteer'
      and role.is_active
  ) then
    raise exception 'A club-assigned volunteer role is required';
  end if;
  if not exists (
    select 1 from public.file_records file
    where file.id=document_file_id
      and file.owner_id=actor
      and file.visibility='private'
      and file.related_entity_type='wwcc_submission'
      and file.related_entity_id=submission_id
  ) then
    raise exception 'The private supporting document is invalid';
  end if;

  select id into previous_id
  from public.wwcc_submissions
  where user_id=actor
  order by submitted_at desc
  limit 1;

  insert into public.wwcc_submissions(
    id,user_id,role_assignment_id,legal_name,wwcc_number,expiry_date,
    notes,document_file_id,status,supersedes_submission_id
  )
  values (
    submission_id,actor,assignment_id,trim(legal_name),
    upper(regexp_replace(trim(wwcc_number),'\s+','','g')),expiry_date,
    nullif(trim(coalesce(submission_notes,'')),''),document_file_id,
    'pending',previous_id
  )
  returning id into saved_id;

  insert into public.member_compliance(
    user_id,volunteer_status,wwcc_number,wwcc_status,wwcc_expiry_date,
    wwcc_verification_name,wwcc_notes
  )
  values (
    actor,'pending',upper(regexp_replace(trim(wwcc_number),'\s+','','g')),
    'pending_verification',expiry_date,trim(legal_name),
    nullif(trim(coalesce(submission_notes,'')),'')
  )
  on conflict(user_id) do update set
    volunteer_status='pending',
    volunteer_reason='WWCC submission awaiting review',
    wwcc_number=excluded.wwcc_number,
    wwcc_status='pending_verification',
    wwcc_expiry_date=excluded.wwcc_expiry_date,
    wwcc_verification_name=excluded.wwcc_verification_name,
    wwcc_notes=excluded.wwcc_notes,
    updated_at=now();

  update public.user_role_assignments
  set status='pending',updated_at=now()
  where id=assignment_id and user_id=actor and revoked_at is null;

  insert into public.notifications(
    recipient_id,title,body,category,action_url,dedupe_key,
    related_entity_type,related_entity_id
  )
  values (
    actor,'WWCC submission received',
    'Your Working With Children Check submission is pending review.',
    'roles','/portal/roles/#wwcc',
    'wwcc-submitted:'||saved_id,
    'wwcc_submission',saved_id
  )
  on conflict(recipient_id,dedupe_key) where dedupe_key is not null do nothing;

  perform app_private.write_audit_log(
    'wwcc_submission.created','wwcc_submission',saved_id,null,
    jsonb_build_object(
      'user_id',actor,
      'expiry_date',expiry_date,
      'wwcc_last4',right(upper(regexp_replace(trim(wwcc_number),'\s+','','g')),4),
      'document_file_id',document_file_id
    ),
    'Submitted for WWCC review'
  );
  return saved_id;
end;
$$;

revoke all on function public.submit_wwcc_submission(uuid,uuid,text,text,date,uuid,text)
  from public,anon;
grant execute on function public.submit_wwcc_submission(uuid,uuid,text,text,date,uuid,text)
  to authenticated,service_role;

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
    review_reason=trim(decision_reason)
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

-- Retire the roster/recruitment API surface without deleting production history.
revoke execute on function public.update_member_compliance(uuid,text,text,text,text,text,date,text,text) from authenticated;
revoke execute on function public.request_volunteer_shift(uuid) from authenticated;
revoke execute on function public.update_volunteer_assignment(uuid,text,text) from authenticated;
revoke execute on function public.update_volunteer_shift_status(uuid,text,text) from authenticated;

comment on table public.volunteer_opportunities is
  'Legacy volunteer recruitment data retained for controlled cleanup; no longer used by the application.';
comment on table public.volunteer_shifts is
  'Legacy volunteer roster data retained for controlled cleanup; no longer used by the application.';
comment on table public.volunteer_assignments is
  'Legacy volunteer roster history retained for controlled cleanup; no longer used by the application.';
