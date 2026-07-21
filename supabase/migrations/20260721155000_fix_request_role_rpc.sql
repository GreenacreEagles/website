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
  where id = $1
    and is_system
    and may_request
    and key <> 'super_administrator';

  if not found then
    raise exception 'This role is not available for portal requests';
  end if;

  if target_role.requires_team_scope and $2 is null then
    raise exception 'Select a team for this role request';
  end if;

  if target_role.requires_season_scope and $3 is null then
    raise exception 'Select a season for this role request';
  end if;

  if coalesce(length(trim($4)), 0) < 10 then
    raise exception 'Tell us a little more about the access you need';
  end if;

  if exists (
    select 1
    from public.role_requests rr
    where rr.requester_id = auth.uid()
      and rr.requested_role_id = $1
      and rr.status in ('draft','submitted','under_review')
      and rr.team_id is not distinct from $2
      and rr.season_id is not distinct from $3
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
    $1,
    $2,
    $3,
    trim($4),
    nullif(trim(coalesce($5, '')), ''),
    nullif(trim(coalesce($6, '')), ''),
    trim($4),
    'submitted',
    now()
  )
  returning id into request_id;

  perform app_private.write_audit_log(
    'role_request.submitted',
    'role_request',
    request_id,
    null,
    jsonb_build_object('requester_id', auth.uid(), 'role_id', $1, 'team_id', $2, 'season_id', $3),
    trim($4)
  );

  return request_id;
end;
$$;

grant execute on function public.request_role(uuid, uuid, uuid, text, text, text) to authenticated;
