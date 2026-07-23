-- Capacity-aware volunteer shift signup, assignment lifecycle and shift status operations.

create index if not exists volunteer_assignments_shift_status_idx
on public.volunteer_assignments (shift_id, status);

create index if not exists volunteer_shifts_status_starts_idx
on public.volunteer_shifts (status, starts_at);

create or replace function app_private.refresh_volunteer_shift_status(target_shift_id uuid)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  shift_row public.volunteer_shifts%rowtype;
  active_count int;
  next_status text;
begin
  select *
  into shift_row
  from public.volunteer_shifts
  where id = target_shift_id
  for update;

  if not found then
    raise exception 'Volunteer shift not found';
  end if;

  if shift_row.status in ('cancelled','completed') then
    return shift_row.status;
  end if;

  select count(*)::int
  into active_count
  from public.volunteer_assignments
  where shift_id = target_shift_id
    and status in ('interested','assigned','checked_in','replacement_requested');

  next_status := case when active_count >= shift_row.capacity then 'filled' else 'open' end;

  update public.volunteer_shifts
  set status = next_status,
      updated_at = now()
  where id = target_shift_id
  returning status into next_status;

  return next_status;
end;
$$;

create or replace function public.request_volunteer_shift(target_shift_id uuid)
returns table (
  assignment_id uuid,
  assignment_status text,
  shift_status text
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  shift_row public.volunteer_shifts%rowtype;
  opportunity_row public.volunteer_opportunities%rowtype;
  assignment_row public.volunteer_assignments%rowtype;
  active_count int;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select *
  into shift_row
  from public.volunteer_shifts
  where id = target_shift_id
  for update;

  if not found then
    raise exception 'Volunteer shift not found';
  end if;

  select *
  into opportunity_row
  from public.volunteer_opportunities
  where id = shift_row.opportunity_id;

  if not found or opportunity_row.status <> 'active' then
    raise exception 'Volunteer opportunity is not active';
  end if;

  if shift_row.status not in ('open','filled') then
    raise exception 'Volunteer shift is not open';
  end if;

  if shift_row.starts_at <= now() then
    raise exception 'Volunteer shift has already started';
  end if;

  if opportunity_row.required_permission is not null
    and trim(opportunity_row.required_permission) <> ''
    and not app_private.has_permission(opportunity_row.required_permission)
  then
    raise exception 'This shift requires additional club permission';
  end if;

  select *
  into assignment_row
  from public.volunteer_assignments
  where shift_id = target_shift_id
    and user_id = auth.uid()
  for update;

  if found and assignment_row.status in ('interested','assigned','checked_in','replacement_requested') then
    return query select assignment_row.id, assignment_row.status, shift_row.status;
    return;
  end if;

  select count(*)::int
  into active_count
  from public.volunteer_assignments
  where shift_id = target_shift_id
    and status in ('interested','assigned','checked_in','replacement_requested');

  if active_count >= shift_row.capacity then
    perform app_private.refresh_volunteer_shift_status(target_shift_id);
    raise exception 'Volunteer shift is full';
  end if;

  insert into public.volunteer_assignments (
    shift_id,
    user_id,
    status,
    checked_in_at,
    completed_at
  )
  values (
    target_shift_id,
    auth.uid(),
    'assigned',
    null,
    null
  )
  on conflict (shift_id, user_id) do update
    set status = 'assigned',
        checked_in_at = null,
        completed_at = null,
        updated_at = now()
  returning * into assignment_row;

  shift_row.status := app_private.refresh_volunteer_shift_status(target_shift_id);

  insert into public.notifications (recipient_id, title, body, related_entity_type, related_entity_id)
  values (auth.uid(), 'Volunteer shift confirmed', 'You have been added to a club volunteer shift.', 'volunteer_assignment', assignment_row.id);

  perform app_private.write_audit_log('volunteer.assignment_requested', 'volunteer_assignment', assignment_row.id, null, to_jsonb(assignment_row), null);

  return query select assignment_row.id, assignment_row.status, shift_row.status;
end;
$$;

create or replace function public.update_volunteer_assignment(
  target_assignment_id uuid,
  target_status text,
  note text default null
)
returns table (
  assignment_id uuid,
  assignment_status text,
  shift_status text
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  assignment_row public.volunteer_assignments%rowtype;
  old_assignment public.volunteer_assignments%rowtype;
  shift_row public.volunteer_shifts%rowtype;
  safe_status text;
  is_manager boolean;
  next_shift_status text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  safe_status := lower(coalesce(nullif(trim(target_status), ''), ''));
  is_manager := app_private.has_permission('volunteers.manage');

  if safe_status not in ('interested','assigned','checked_in','completed','cancelled','replacement_requested') then
    raise exception 'Invalid volunteer assignment status';
  end if;

  select *
  into assignment_row
  from public.volunteer_assignments
  where id = target_assignment_id
  for update;

  if not found then
    raise exception 'Volunteer assignment not found';
  end if;

  if assignment_row.user_id <> auth.uid() and not is_manager then
    raise exception 'Not authorised';
  end if;

  if not is_manager and safe_status not in ('checked_in','cancelled','replacement_requested') then
    raise exception 'Not authorised for this status';
  end if;

  select *
  into shift_row
  from public.volunteer_shifts
  where id = assignment_row.shift_id
  for update;

  if not found then
    raise exception 'Volunteer shift not found';
  end if;

  if not is_manager and shift_row.status in ('cancelled','completed') then
    raise exception 'Volunteer shift is closed';
  end if;

  if not is_manager and safe_status = 'checked_in' and now() < shift_row.starts_at - interval '3 hours' then
    raise exception 'Check-in is not open yet';
  end if;

  old_assignment := assignment_row;

  update public.volunteer_assignments
  set status = safe_status,
      checked_in_at = case
        when safe_status in ('checked_in','completed') then coalesce(checked_in_at, now())
        when safe_status = 'cancelled' then null
        else checked_in_at
      end,
      completed_at = case
        when safe_status = 'completed' then coalesce(completed_at, now())
        when safe_status = 'cancelled' then null
        else completed_at
      end,
      updated_at = now()
  where id = assignment_row.id
  returning * into assignment_row;

  next_shift_status := app_private.refresh_volunteer_shift_status(assignment_row.shift_id);

  if is_manager and assignment_row.user_id <> auth.uid() then
    insert into public.notifications (recipient_id, title, body, related_entity_type, related_entity_id)
    values (
      assignment_row.user_id,
      'Volunteer shift updated',
      'A club volunteer coordinator updated one of your volunteer shifts.',
      'volunteer_assignment',
      assignment_row.id
    );
  end if;

  perform app_private.write_audit_log('volunteer.assignment_updated', 'volunteer_assignment', assignment_row.id, to_jsonb(old_assignment), to_jsonb(assignment_row), note);

  return query select assignment_row.id, assignment_row.status, next_shift_status;
end;
$$;

create or replace function public.update_volunteer_shift_status(
  target_shift_id uuid,
  target_status text,
  note text default null
)
returns table (
  shift_id uuid,
  shift_status text,
  affected_assignments int
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  shift_row public.volunteer_shifts%rowtype;
  old_shift public.volunteer_shifts%rowtype;
  safe_status text;
  changed_count int := 0;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not app_private.has_permission('volunteers.manage') then
    raise exception 'Not authorised';
  end if;

  safe_status := lower(coalesce(nullif(trim(target_status), ''), ''));

  if safe_status not in ('open','filled','cancelled','completed') then
    raise exception 'Invalid volunteer shift status';
  end if;

  select *
  into shift_row
  from public.volunteer_shifts
  where id = target_shift_id
  for update;

  if not found then
    raise exception 'Volunteer shift not found';
  end if;

  old_shift := shift_row;

  update public.volunteer_shifts
  set status = safe_status,
      updated_at = now()
  where id = target_shift_id
  returning * into shift_row;

  if safe_status = 'cancelled' then
    update public.volunteer_assignments
    set status = 'cancelled',
        checked_in_at = null,
        completed_at = null,
        updated_at = now()
    where shift_id = target_shift_id
      and status in ('interested','assigned','checked_in','replacement_requested');

    get diagnostics changed_count = row_count;

    insert into public.notifications (recipient_id, title, body, related_entity_type, related_entity_id)
    select user_id, 'Volunteer shift cancelled', 'A club volunteer shift you were assigned to has been cancelled.', 'volunteer_assignment', id
    from public.volunteer_assignments
    where shift_id = target_shift_id
      and status = 'cancelled';
  elsif safe_status = 'completed' then
    update public.volunteer_assignments
    set status = 'completed',
        checked_in_at = coalesce(checked_in_at, now()),
        completed_at = coalesce(completed_at, now()),
        updated_at = now()
    where shift_id = target_shift_id
      and status in ('assigned','checked_in');

    get diagnostics changed_count = row_count;
  else
    shift_row.status := app_private.refresh_volunteer_shift_status(target_shift_id);
  end if;

  perform app_private.write_audit_log('volunteer.shift_updated', 'volunteer_shift', shift_row.id, to_jsonb(old_shift), to_jsonb(shift_row), note);

  return query select shift_row.id, shift_row.status, changed_count;
end;
$$;

drop policy if exists volunteer_assignments_manage on public.volunteer_assignments;
drop policy if exists volunteer_assignments_admin_manage on public.volunteer_assignments;
create policy volunteer_assignments_admin_manage
on public.volunteer_assignments
for all
to authenticated
using (app_private.has_permission('volunteers.manage'))
with check (app_private.has_permission('volunteers.manage'));

grant select on public.volunteer_opportunities to authenticated;
grant select on public.volunteer_shifts to authenticated;
grant select on public.volunteer_assignments to authenticated;

revoke all on function public.request_volunteer_shift(uuid) from public;
revoke all on function public.update_volunteer_assignment(uuid, text, text) from public;
revoke all on function public.update_volunteer_shift_status(uuid, text, text) from public;

grant execute on function public.request_volunteer_shift(uuid) to authenticated;
grant execute on function public.update_volunteer_assignment(uuid, text, text) to authenticated;
grant execute on function public.update_volunteer_shift_status(uuid, text, text) to authenticated;
