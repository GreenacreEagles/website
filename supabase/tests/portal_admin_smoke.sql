begin;

create temp table smoke_results (check_name text, passed boolean, detail text);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
('00000000-0000-4000-8000-000000000211','00000000-0000-0000-0000-000000000000','authenticated','authenticated','portal-admin-test@example.invalid','',now(),'{"provider":"email","providers":["email"]}'::jsonb,'{"full_name":"Portal Admin Test"}'::jsonb,now(),now()),
('00000000-0000-4000-8000-000000000212','00000000-0000-0000-0000-000000000000','authenticated','authenticated','portal-user-test@example.invalid','',now(),'{"provider":"email","providers":["email"]}'::jsonb,'{"full_name":"Portal User Test","role":"super_administrator"}'::jsonb,now(),now());

insert into public.seasons (id, name, year, starts_on, ends_on, status)
values ('00000000-0000-4000-8000-000000000213', 'Smoke Test Season', 2027, '2027-01-01', '2027-12-31', 'active');

insert into public.teams (id, season_id, name, division, status)
values ('00000000-0000-4000-8000-000000000214', '00000000-0000-4000-8000-000000000213', 'Smoke Test Team', 'Blue', 'active');

select app_private.bootstrap_super_admin('00000000-0000-4000-8000-000000000211', 'Rollback smoke test bootstrap for portal admin RPCs');

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000212', true);

insert into smoke_results
select 'general user cannot assign roles', not public.has_permission('roles.assign'), 'roles.assign false';

insert into smoke_results
select 'metadata cannot create super admin',
  not exists(
    select 1
    from public.user_role_assignments ura
    join public.roles r on r.id = ura.role_id
    where ura.user_id = '00000000-0000-4000-8000-000000000212'
      and r.key = 'super_administrator'
  ),
  'raw_user_meta_data ignored';

insert into smoke_results
select 'role request creation is disabled',
  not has_function_privilege('authenticated', 'public.request_role(uuid, uuid, uuid, text, text, text)', 'execute'),
  'authenticated cannot execute request_role';

do $$
begin
  perform public.assign_user_role('00000000-0000-4000-8000-000000000212', (select id from public.roles where key = 'coach'), '00000000-0000-4000-8000-000000000214', '00000000-0000-4000-8000-000000000213', now(), null, 'General user should not be able to assign roles');
  insert into smoke_results values ('general user cannot assign via RPC', false, 'unexpected success');
exception when others then
  insert into smoke_results values ('general user cannot assign via RPC', true, sqlerrm);
end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000211', true);

select public.assign_user_role(
  '00000000-0000-4000-8000-000000000212',
  (select id from public.roles where key = 'coach'),
  '00000000-0000-4000-8000-000000000214',
  '00000000-0000-4000-8000-000000000213',
  now(),
  now() + interval '30 days',
  'Assign coach role during rollback smoke test'
);

insert into smoke_results
select 'super admin can assign scoped coach role',
  exists(
    select 1
    from public.user_role_assignments ura
    join public.roles r on r.id = ura.role_id
    where ura.user_id = '00000000-0000-4000-8000-000000000212'
      and r.key = 'coach'
      and ura.team_id = '00000000-0000-4000-8000-000000000214'
  ),
  'assignment inserted';

insert into smoke_results
select 'assigned team appears in member team rpc',
  exists (
    select 1
    from public.member_team_ids()
    where team_id = '00000000-0000-4000-8000-000000000214'
      and relationship = 'role'
  ),
  'member_team_ids includes assigned team';

insert into public.team_staff (team_id, user_id, staff_role, status)
values ('00000000-0000-4000-8000-000000000214', '00000000-0000-4000-8000-000000000212', 'team_manager', 'active');

insert into smoke_results
select 'team staff can manage team operations',
  app_private.can_manage_team_operations('00000000-0000-4000-8000-000000000214'),
  'team manager assignment permits team posts and reports';

insert into public.match_reports (team_id, author_id, final_score_for, final_score_against, result, highlights, status)
values ('00000000-0000-4000-8000-000000000214', '00000000-0000-4000-8000-000000000212', 2, 1, 'win', 'Smoke test report', 'submitted');

insert into smoke_results
select 'team staff report can be saved',
  exists (
    select 1
    from public.match_reports
    where team_id = '00000000-0000-4000-8000-000000000214'
      and author_id = '00000000-0000-4000-8000-000000000212'
      and status = 'submitted'
  ),
  'match report inserted for active team staff';

select check_name, passed, detail from smoke_results order by check_name;

rollback;
