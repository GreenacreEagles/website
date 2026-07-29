-- Record an authenticated adult declaration before beginning the volunteer WWCC workflow.
-- WWCC identity details, including date of birth, remain in the separate private submission.

alter table public.member_compliance
  add column if not exists adult_confirmed boolean not null default false,
  add column if not exists adult_confirmed_at timestamptz,
  add column if not exists adult_confirmed_by uuid references public.profiles(id) on delete set null,
  add column if not exists volunteer_requested_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.member_compliance'::regclass
      and conname = 'member_compliance_adult_confirmation_check'
  ) then
    alter table public.member_compliance
      add constraint member_compliance_adult_confirmation_check
      check (
        (adult_confirmed and adult_confirmed_at is not null and adult_confirmed_by = user_id)
        or
        (not adult_confirmed and adult_confirmed_at is null and adult_confirmed_by is null)
      ) not valid;
    alter table public.member_compliance
      validate constraint member_compliance_adult_confirmation_check;
  end if;
end
$$;

revoke all on function public.request_volunteer_role() from public, anon, authenticated, service_role;
drop function public.request_volunteer_role();

create function public.request_volunteer_role(adult_confirmation boolean)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  volunteer_role_id uuid;
  assignment_id uuid;
  prior_confirmation boolean;
begin
  if actor is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(actor::text, 0));
  end if;
  if actor is null then raise exception 'You must be signed in'; end if;
  if adult_confirmation is distinct from true then
    raise exception 'You must confirm that you are 18 years of age or older';
  end if;
  if exists (select 1 from public.managed_child_accounts where child_user_id = actor) then
    raise exception 'Child accounts cannot request volunteer access';
  end if;

  select id into volunteer_role_id
  from public.roles where key = 'volunteer' and is_active;
  if volunteer_role_id is null then raise exception 'The volunteer role is not available'; end if;

  select adult_confirmed into prior_confirmation
  from public.member_compliance where user_id = actor;

  select id into assignment_id
  from public.user_role_assignments
  where user_id = actor and role_id = volunteer_role_id and revoked_at is null
  order by created_at desc limit 1;

  if assignment_id is null then
    insert into public.user_role_assignments (user_id, role_id, status, reason, starts_at)
    values (actor, volunteer_role_id, 'pending', 'Member confirmed adult status; WWCC review required', now())
    returning id into assignment_id;
  end if;

  insert into public.member_compliance (
    user_id, volunteer_status, wwcc_status, adult_confirmed,
    adult_confirmed_at, adult_confirmed_by, volunteer_requested_at
  ) values (actor, 'pending', 'not_supplied', true, now(), actor, now())
  on conflict (user_id) do update set
    adult_confirmed = true,
    adult_confirmed_at = coalesce(public.member_compliance.adult_confirmed_at, excluded.adult_confirmed_at),
    adult_confirmed_by = coalesce(public.member_compliance.adult_confirmed_by, excluded.adult_confirmed_by),
    volunteer_requested_at = coalesce(public.member_compliance.volunteer_requested_at, excluded.volunteer_requested_at);

  perform app_private.write_audit_log(
    'volunteer.adult_confirmed', 'user_role_assignment', assignment_id,
    jsonb_build_object('user_id', actor, 'adult_confirmed', coalesce(prior_confirmation, false)),
    jsonb_build_object('user_id', actor, 'adult_confirmed', true, 'adult_confirmed_by', actor),
    'Member confirmed adult status and requested volunteer access'
  );
  return assignment_id;
end
$$;

revoke all on function public.request_volunteer_role(boolean) from public, anon;
grant execute on function public.request_volunteer_role(boolean) to authenticated, service_role;
