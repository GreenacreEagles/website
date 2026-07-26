begin;

do $$
begin
  if has_function_privilege('anon', 'public.get_portal_context()', 'execute') then
    raise exception 'anon must not execute get_portal_context';
  end if;
  if has_function_privilege('anon', 'public.has_any_permission(text[],uuid,uuid)', 'execute') then
    raise exception 'anon must not execute has_any_permission';
  end if;
  if has_function_privilege('anon', 'public.process_payment_webhook(text,text,text,text,uuid,text,jsonb)', 'execute') then
    raise exception 'anon must not execute process_payment_webhook';
  end if;
  if has_function_privilege('authenticated', 'public.process_payment_webhook(text,text,text,text,uuid,text,jsonb)', 'execute') then
    raise exception 'authenticated must not execute process_payment_webhook';
  end if;
  if not has_function_privilege('service_role', 'public.process_payment_webhook(text,text,text,text,uuid,text,jsonb)', 'execute') then
    raise exception 'service_role must execute process_payment_webhook';
  end if;
end;
$$;

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
  '00000000-0000-4000-8000-000000000777',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'portal-context-test@example.invalid',
  '',
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"full_name":"Portal Context Test"}'::jsonb,
  now(),
  now()
);

insert into public.user_role_assignments (user_id, role_id, status, starts_at, reason)
select
  '00000000-0000-4000-8000-000000000777',
  role.id,
  'active',
  now() - interval '1 minute',
  'Portal context smoke test'
from public.roles role
where role.key = 'super_administrator';

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000777","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  context jsonb;
begin
  context := public.get_portal_context();
  if context->>'user_id' <> '00000000-0000-4000-8000-000000000777' then
    raise exception 'portal context returned the wrong user';
  end if;
  if context->'profile'->>'full_name' <> 'Portal Context Test' then
    raise exception 'portal context profile is missing';
  end if;
  if not public.has_any_permission(array['content.manage']) then
    raise exception 'set-based permission lookup did not preserve wildcard access';
  end if;
end;
$$;

rollback;
