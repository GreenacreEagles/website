-- Harden an existing helper that was present before the platform migration.
-- Supabase advisors flagged it as a SECURITY DEFINER function executable by
-- anon/authenticated users through the exposed public schema.

do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'rls_auto_enable'
      and pg_get_function_identity_arguments(p.oid) = ''
  ) then
    revoke execute on function public.rls_auto_enable() from anon;
    revoke execute on function public.rls_auto_enable() from authenticated;
    revoke execute on function public.rls_auto_enable() from public;
  end if;
end;
$$;
