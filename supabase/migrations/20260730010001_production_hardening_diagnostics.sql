-- Read-only integrity diagnostics and wallet reconciliation.
-- These functions never mutate balances or repair production records.

create or replace function public.diagnose_data_integrity()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
begin
  if actor is null or not app_private.has_permission('users.manage') then
    raise exception 'Not authorised';
  end if;

  return jsonb_build_object(
    'generated_at', now(),
    'auth_users_without_profile', coalesce((
      select jsonb_agg(jsonb_build_object('user_id', u.id, 'email', u.email))
      from auth.users u
      left join public.profiles p on p.id = u.id
      where p.id is null
      limit 100
    ), '[]'::jsonb),
    'profiles_without_role', coalesce((
      select jsonb_agg(jsonb_build_object('profile_id', p.id, 'full_name', p.full_name))
      from public.profiles p
      where not exists (
        select 1 from public.user_role_assignments ura
        where ura.user_id = p.id and ura.status = 'active' and ura.revoked_at is null
      )
      limit 100
    ), '[]'::jsonb),
    'profiles_without_wallet', coalesce((
      select jsonb_agg(jsonb_build_object('profile_id', p.id, 'full_name', p.full_name))
      from public.profiles p
      where not exists (
        select 1 from public.wallet_accounts wa where wa.owner_id = p.id and wa.account_type = 'user'
      )
      limit 100
    ), '[]'::jsonb),
    'children_without_family', coalesce((
      select jsonb_agg(jsonb_build_object('child_user_id', m.child_user_id, 'username', m.username))
      from public.managed_child_accounts m
      where m.family_id is null
         or not exists (
           select 1 from public.family_members fm
           where fm.user_id = m.child_user_id and fm.status = 'active'
         )
      limit 100
    ), '[]'::jsonb),
    'duplicate_active_roles', coalesce((
      select jsonb_agg(jsonb_build_object('user_id', x.user_id, 'role_id', x.role_id, 'count', x.cnt))
      from (
        select ura.user_id, ura.role_id, count(*)::integer as cnt
        from public.user_role_assignments ura
        where ura.status = 'active' and ura.revoked_at is null
        group by ura.user_id, ura.role_id, ura.team_id, ura.season_id
        having count(*) > 1
        limit 100
      ) x
    ), '[]'::jsonb),
    'duplicate_wallets', coalesce((
      select jsonb_agg(jsonb_build_object('owner_id', x.owner_id, 'count', x.cnt))
      from (
        select wa.owner_id, count(*)::integer as cnt
        from public.wallet_accounts wa
        where wa.owner_id is not null and wa.account_type = 'user'
        group by wa.owner_id
        having count(*) > 1
        limit 100
      ) x
    ), '[]'::jsonb),
    'duplicate_voucher_redemptions', coalesce((
      select jsonb_agg(jsonb_build_object('voucher_id', x.voucher_id, 'redeemed_by', x.redeemed_by, 'count', x.cnt))
      from (
        select vr.voucher_id, vr.redeemed_by, count(*)::integer as cnt
        from public.voucher_redemptions vr
        where vr.status = 'completed'
        group by vr.voucher_id, vr.redeemed_by, vr.amount_cents, vr.created_at
        having count(*) > 1
        limit 100
      ) x
    ), '[]'::jsonb),
    'orphaned_canteen_order_items', coalesce((
      select jsonb_agg(jsonb_build_object('item_id', i.id, 'order_id', i.order_id))
      from public.canteen_order_items i
      left join public.canteen_orders o on o.id = i.order_id
      where o.id is null
      limit 100
    ), '[]'::jsonb),
    'orphaned_merchandise_order_items', coalesce((
      select jsonb_agg(jsonb_build_object('item_id', i.id, 'order_id', i.order_id))
      from public.merchandise_order_items i
      left join public.merchandise_orders o on o.id = i.order_id
      where o.id is null
      limit 100
    ), '[]'::jsonb),
    'invalid_canteen_order_status', coalesce((
      select jsonb_agg(jsonb_build_object('order_id', o.id, 'order_status', o.order_status, 'payment_status', o.payment_status))
      from public.canteen_orders o
      where (o.order_status = 'collected' and o.payment_status <> 'paid')
         or (o.order_status = 'awaiting_payment' and o.payment_status = 'paid')
      limit 100
    ), '[]'::jsonb),
    'expired_wwcc_still_active', coalesce((
      select jsonb_agg(jsonb_build_object('user_id', mc.user_id, 'wwcc_status', mc.wwcc_status, 'expiry', mc.wwcc_expiry_date))
      from public.member_compliance mc
      where mc.wwcc_status in ('verified', 'active', 'approved')
        and mc.wwcc_expiry_date is not null
        and mc.wwcc_expiry_date < current_date
      limit 100
    ), '[]'::jsonb),
    'incomplete_child_provisioning', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'username', p.username, 'status', p.status, 'auth_user_id', p.auth_user_id, 'updated_at', p.updated_at
      ))
      from public.child_account_provisioning p
      where p.status in ('started', 'auth_created', 'failed')
      order by p.updated_at desc
      limit 100
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.diagnose_data_integrity() from public, anon;
grant execute on function public.diagnose_data_integrity() to authenticated, service_role;

create or replace function public.diagnose_wallet_reconciliation(sample_limit integer default 100)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  lim integer := least(greatest(coalesce(sample_limit, 100), 1), 500);
begin
  if actor is null or not (
    app_private.has_permission('wallet.adjust')
    or app_private.has_permission('users.manage')
  ) then
    raise exception 'Not authorised';
  end if;

  return jsonb_build_object(
    'generated_at', now(),
    'note', 'Read-only diagnostic. Does not alter balances.',
    'mismatches', coalesce((
      select jsonb_agg(row_to_json(x))
      from (
        select
          wa.id as wallet_account_id,
          wa.owner_id,
          wa.family_id,
          wa.status,
          coalesce(app_private.wallet_balance_cents(wa.id), 0) as derived_balance_cents,
          coalesce((
            select sum(le.amount_cents)::bigint
            from public.wallet_ledger_entries le
            where le.wallet_account_id = wa.id
          ), 0) as ledger_sum_cents
        from public.wallet_accounts wa
        order by wa.created_at desc
        limit lim
      ) x
      where x.derived_balance_cents <> x.ledger_sum_cents
    ), '[]'::jsonb),
    'sampled_wallets', lim
  );
end;
$$;

revoke all on function public.diagnose_wallet_reconciliation(integer) from public, anon;
grant execute on function public.diagnose_wallet_reconciliation(integer) to authenticated, service_role;

create or replace function public.diagnose_r2_file_orphans(sample_limit integer default 100)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  lim integer := least(greatest(coalesce(sample_limit, 100), 1), 500);
begin
  if actor is null or not app_private.has_permission('users.manage') then
    raise exception 'Not authorised';
  end if;

  return jsonb_build_object(
    'generated_at', now(),
    'note', 'Metadata-only check. Missing R2 objects require Worker/R2 inventory comparison.',
    'file_records_without_owner', coalesce((
      select jsonb_agg(jsonb_build_object('id', fr.id, 'object_path', fr.object_path, 'bucket', fr.bucket))
      from public.file_records fr
      where fr.owner_id is not null
        and not exists (select 1 from public.profiles p where p.id = fr.owner_id)
      limit lim
    ), '[]'::jsonb),
    'wwcc_submissions_missing_file', coalesce((
      select jsonb_agg(jsonb_build_object('submission_id', s.id, 'user_id', s.user_id, 'status', s.status))
      from public.wwcc_submissions s
      where s.document_file_id is not null
        and not exists (select 1 from public.file_records fr where fr.id = s.document_file_id)
      limit lim
    ), '[]'::jsonb),
    'unreferenced_private_file_records', coalesce((
      select jsonb_agg(jsonb_build_object('id', fr.id, 'object_path', fr.object_path, 'related_entity_type', fr.related_entity_type))
      from public.file_records fr
      where fr.visibility = 'private'
        and fr.related_entity_type = 'wwcc_submission'
        and fr.related_entity_id is not null
        and not exists (
          select 1 from public.wwcc_submissions s
          where s.id = fr.related_entity_id or s.document_file_id = fr.id
        )
      limit lim
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.diagnose_r2_file_orphans(integer) from public, anon;
grant execute on function public.diagnose_r2_file_orphans(integer) to authenticated, service_role;
