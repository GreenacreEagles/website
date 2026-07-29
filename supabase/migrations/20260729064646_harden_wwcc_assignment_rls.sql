-- Keep roles private while allowing a member to submit against their own current volunteer assignment.
create or replace function app_private.is_current_volunteer_assignment(target_assignment_id uuid,target_user_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select target_user_id=(select auth.uid()) and exists(
  select 1 from public.user_role_assignments a join public.roles r on r.id=a.role_id
  where a.id=target_assignment_id and a.user_id=target_user_id and a.revoked_at is null
   and a.status in ('pending','active','suspended','expired') and r.key='volunteer' and r.is_active
 );
$$;
revoke all on function app_private.is_current_volunteer_assignment(uuid,uuid) from public,anon;
grant execute on function app_private.is_current_volunteer_assignment(uuid,uuid) to authenticated,service_role;
drop policy if exists wwcc_submissions_insert_own on public.wwcc_submissions;
create policy wwcc_submissions_insert_own on public.wwcc_submissions for insert to authenticated with check(
 user_id=(select auth.uid()) and status='pending' and reviewed_by is null and reviewed_at is null
 and clearance_type in ('volunteer','paid_worker')
 and app_private.is_current_volunteer_assignment(role_assignment_id,user_id)
 and (document_file_id is null or exists(select 1 from public.file_records f where f.id=document_file_id
  and f.owner_id=(select auth.uid()) and f.visibility='private' and f.related_entity_type='wwcc_submission' and f.related_entity_id=id))
);
