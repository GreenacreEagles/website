begin;

insert into auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) values (
  '00000000-0000-4000-8000-000000000102',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'foundation-smoke-test@example.invalid',
  '',
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"full_name":"Foundation Smoke Test","role":"super_admin"}'::jsonb,
  now(),
  now()
);

select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000102', true);

select
  exists(select 1 from public.profiles where id = '00000000-0000-4000-8000-000000000102') as profile_created,
  exists(
    select 1
    from public.user_role_assignments ura
    join public.roles r on r.id = ura.role_id
    where ura.user_id = '00000000-0000-4000-8000-000000000102'
      and r.key = 'general_user'
      and ura.revoked_at is null
  ) as general_role_assigned,
  exists(
    select 1
    from public.user_role_assignments ura
    join public.roles r on r.id = ura.role_id
    where ura.user_id = '00000000-0000-4000-8000-000000000102'
      and r.key = 'super_admin'
      and ura.revoked_at is null
  ) as metadata_super_admin_assigned,
  public.has_permission('roles.read') as can_read_roles,
  public.has_permission('canteen.orders.manage') as can_manage_canteen,
  public.has_permission('content.manage') as can_manage_content;

rollback;
