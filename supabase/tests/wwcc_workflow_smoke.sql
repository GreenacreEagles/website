begin;

do $$
begin
  if not exists(select 1 from public.roles where key='volunteer' and role_kind='global' and is_active) then
    raise exception 'Volunteer global role is missing';
  end if;
  if not exists(select 1 from public.permissions where key='wwcc.view') or
     not exists(select 1 from public.permissions where key='wwcc.verify') then
    raise exception 'WWCC permissions are missing';
  end if;
  if not has_function_privilege(
    'authenticated',
    'public.submit_wwcc_submission(uuid,uuid,text,text,date,uuid,text)',
    'execute'
  ) then
    raise exception 'Authenticated volunteers cannot submit WWCC records';
  end if;
  if not has_function_privilege(
    'authenticated',
    'public.review_wwcc_submission(uuid,text,text,date,text)',
    'execute'
  ) then
    raise exception 'Authenticated reviewers cannot call the guarded review RPC';
  end if;
  if has_function_privilege(
    'authenticated',
    'public.update_member_compliance(uuid,text,text,text,text,text,date,text,text)',
    'execute'
  ) then
    raise exception 'Legacy compliance RPC remains executable';
  end if;
  if has_function_privilege('authenticated','public.request_volunteer_shift(uuid)','execute') or
     has_function_privilege('authenticated','public.update_volunteer_assignment(uuid,text,text)','execute') or
     has_function_privilege('authenticated','public.update_volunteer_shift_status(uuid,text,text)','execute') then
    raise exception 'Legacy volunteer roster RPC remains executable';
  end if;
  if not (select relrowsecurity from pg_class where oid='public.wwcc_submissions'::regclass) then
    raise exception 'WWCC submission RLS is not enabled';
  end if;
  if not exists(
    select 1 from pg_policies
    where schemaname='public' and tablename='wwcc_submissions'
      and policyname='wwcc_submissions_select'
  ) then
    raise exception 'WWCC submission select policy is missing';
  end if;
end;
$$;

rollback;
