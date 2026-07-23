-- Wallet top-up requests, settlement and controlled ledger operations.

alter table public.payments
add column if not exists settled_at timestamptz,
add column if not exists settled_by uuid references public.profiles(id) on delete set null;

create index if not exists payments_status_created_idx
on public.payments (status, created_at);

create index if not exists payments_wallet_metadata_idx
on public.payments ((metadata->>'wallet_account_id'))
where metadata ? 'wallet_account_id';

create unique index if not exists wallet_accounts_owner_user_unique
on public.wallet_accounts (owner_id)
where owner_id is not null and account_type = 'user';

create unique index if not exists wallet_accounts_family_unique
on public.wallet_accounts (family_id)
where family_id is not null and account_type = 'family';

create or replace function public.ensure_wallet_account(
  target_owner_id uuid default null,
  target_family_id uuid default null,
  target_account_type text default 'user'
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  wallet_id uuid;
  safe_account_type text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  safe_account_type := coalesce(nullif(trim(target_account_type), ''), 'user');

  if safe_account_type not in ('user','family') then
    raise exception 'Invalid wallet type';
  end if;

  if safe_account_type = 'user' then
    target_owner_id := coalesce(target_owner_id, auth.uid());
    target_family_id := null;

    if target_owner_id <> auth.uid() and not app_private.has_permission('wallet.adjust') then
      raise exception 'Not authorised';
    end if;

    insert into public.wallet_accounts (owner_id, account_type, status)
    values (target_owner_id, 'user', 'active')
    on conflict (owner_id) where owner_id is not null and account_type = 'user'
    do update set updated_at = now()
    returning id into wallet_id;
  else
    if target_family_id is null then
      raise exception 'Family is required';
    end if;

    if not app_private.has_permission('wallet.adjust') and not exists (
      select 1
      from public.family_members fm
      where fm.family_id = target_family_id
        and fm.user_id = auth.uid()
        and fm.status = 'active'
        and fm.can_manage
    ) then
      raise exception 'Not authorised';
    end if;

    insert into public.wallet_accounts (family_id, account_type, status)
    values (target_family_id, 'family', 'active')
    on conflict (family_id) where family_id is not null and account_type = 'family'
    do update set updated_at = now()
    returning id into wallet_id;
  end if;

  perform app_private.write_audit_log('wallet.account_ensured', 'wallet_account', wallet_id, null, jsonb_build_object('account_type', safe_account_type), null);
  return wallet_id;
end;
$$;

create or replace function app_private.wallet_balance_cents(wallet_id uuid)
returns int
language sql
security definer
set search_path = public, extensions
as $$
  select coalesce((
    select balance_cents
    from public.wallet_balances
    where wallet_account_id = wallet_id
  ), 0)::int;
$$;

create or replace function app_private.can_use_wallet(target_wallet_id uuid)
returns boolean
language sql
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1
    from public.wallet_accounts wa
    where wa.id = target_wallet_id
      and wa.status = 'active'
      and (
        wa.owner_id = auth.uid()
        or app_private.has_permission('wallet.adjust')
        or (
          wa.family_id is not null
          and exists (
            select 1
            from public.family_members fm
            where fm.family_id = wa.family_id
              and fm.user_id = auth.uid()
              and fm.status = 'active'
              and (fm.can_manage or fm.can_spend)
          )
        )
      )
  );
$$;

create or replace function public.create_wallet_top_up(
  target_wallet_id uuid,
  top_up_amount_cents int,
  provider text default 'manual',
  idempotency_key text default null
)
returns table (
  payment_id uuid,
  payment_status text,
  amount_cents int
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  wallet_row public.wallet_accounts%rowtype;
  payment_row public.payments%rowtype;
  safe_provider text;
  safe_key text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if top_up_amount_cents < 100 or top_up_amount_cents > 100000 then
    raise exception 'Top-up amount must be between $1 and $1,000';
  end if;

  select *
  into wallet_row
  from public.wallet_accounts
  where id = target_wallet_id
  for update;

  if not found or wallet_row.status <> 'active' then
    raise exception 'Wallet not available';
  end if;

  if not app_private.can_use_wallet(target_wallet_id) then
    raise exception 'Not authorised for this wallet';
  end if;

  safe_provider := coalesce(nullif(trim(provider), ''), 'manual');
  safe_key := coalesce(nullif(trim(idempotency_key), ''), 'wallet-top-up:' || target_wallet_id || ':' || auth.uid() || ':' || gen_random_uuid());

  insert into public.payments (
    provider,
    payer_id,
    beneficiary_id,
    top_up_amount_cents,
    currency,
    status,
    idempotency_key,
    metadata
  )
  values (
    safe_provider,
    auth.uid(),
    coalesce(wallet_row.owner_id, auth.uid()),
    amount_cents,
    'AUD',
    case when safe_provider = 'manual' then 'created' else 'requires_action' end,
    safe_key,
    jsonb_build_object(
      'purpose', 'wallet_top_up',
      'wallet_account_id', target_wallet_id,
      'wallet_account_type', wallet_row.account_type
    )
  )
  on conflict (idempotency_key) do update
    set idempotency_key = excluded.idempotency_key
  returning * into payment_row;

  perform app_private.write_audit_log('wallet.top_up_created', 'payment', payment_row.id, null, to_jsonb(payment_row), null);

  return query
  select payment_row.id, payment_row.status, payment_row.amount_cents;
end;
$$;

create or replace function public.settle_wallet_top_up(
  target_payment_id uuid,
  target_status text,
  provider_payment_id text default null,
  settlement_note text default null
)
returns table (
  payment_id uuid,
  payment_status text,
  ledger_entry_id uuid
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  payment_row public.payments%rowtype;
  wallet_id uuid;
  entry_id uuid := null;
  old_payment public.payments%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not app_private.has_permission('wallet.adjust') then
    raise exception 'Not authorised';
  end if;

  if target_status not in ('succeeded','failed','cancelled') then
    raise exception 'Invalid settlement status';
  end if;

  select *
  into payment_row
  from public.payments
  where id = target_payment_id
  for update;

  if not found then
    raise exception 'Payment not found';
  end if;

  old_payment := payment_row;

  if payment_row.metadata->>'purpose' <> 'wallet_top_up' then
    raise exception 'Payment is not a wallet top-up';
  end if;

  if payment_row.status = 'succeeded' then
    return query select payment_row.id, payment_row.status, (
      select id
      from public.wallet_ledger_entries
      where related_entity_type = 'payment'
        and related_entity_id = payment_row.id
      limit 1
    );
    return;
  end if;

  if payment_row.status in ('failed','cancelled','refunded','partially_refunded') then
    raise exception 'Payment is already closed';
  end if;

  wallet_id := (payment_row.metadata->>'wallet_account_id')::uuid;

  update public.payments
  set status = target_status,
      provider_payment_id = coalesce(nullif(trim(provider_payment_id), ''), payments.provider_payment_id),
      settled_at = case when target_status = 'succeeded' then now() else settled_at end,
      settled_by = case when target_status = 'succeeded' then auth.uid() else settled_by end,
      metadata = payments.metadata || jsonb_build_object('settlement_note', coalesce(nullif(trim(settlement_note), ''), '')),
      updated_at = now()
  where id = payment_row.id
  returning * into payment_row;

  if target_status = 'succeeded' then
    entry_id := app_private.apply_wallet_entry(
      wallet_id,
      payment_row.amount_cents,
      'credit',
      'top_up',
      'wallet-top-up-payment:' || payment_row.id,
      coalesce(nullif(trim(settlement_note), ''), 'Wallet top-up settled'),
      payment_row.beneficiary_id
    );

    update public.wallet_ledger_entries
    set related_entity_type = 'payment',
        related_entity_id = payment_row.id
    where id = entry_id;
  end if;

  perform app_private.write_audit_log('wallet.top_up_settled', 'payment', payment_row.id, to_jsonb(old_payment), to_jsonb(payment_row), settlement_note);

  return query select payment_row.id, payment_row.status, entry_id;
end;
$$;

create or replace function public.adjust_wallet_balance(
  target_wallet_id uuid,
  amount_cents int,
  direction text,
  transaction_type text,
  description text,
  idempotency_key text default null,
  beneficiary_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  wallet_row public.wallet_accounts%rowtype;
  safe_key text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not app_private.has_permission('wallet.adjust') then
    raise exception 'Not authorised';
  end if;

  if amount_cents <= 0 then
    raise exception 'Invalid amount';
  end if;

  if direction not in ('credit','debit') then
    raise exception 'Invalid direction';
  end if;

  select *
  into wallet_row
  from public.wallet_accounts
  where id = target_wallet_id
  for update;

  if not found or wallet_row.status <> 'active' then
    raise exception 'Wallet not available';
  end if;

  if direction = 'debit' and app_private.wallet_balance_cents(target_wallet_id) < amount_cents then
    raise exception 'Insufficient wallet balance';
  end if;

  safe_key := coalesce(nullif(trim(idempotency_key), ''), 'wallet-adjust:' || target_wallet_id || ':' || auth.uid() || ':' || gen_random_uuid());

  return app_private.apply_wallet_entry(
    target_wallet_id,
    amount_cents,
    direction,
    coalesce(nullif(trim(transaction_type), ''), 'manual_adjustment'),
    safe_key,
    nullif(trim(description), ''),
    beneficiary_id
  );
end;
$$;

create or replace function public.reverse_wallet_ledger_entry(
  target_entry_id uuid,
  reason text
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  original public.wallet_ledger_entries%rowtype;
  reversal_direction text;
  reversal_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not app_private.has_permission('wallet.adjust') then
    raise exception 'Not authorised';
  end if;

  select *
  into original
  from public.wallet_ledger_entries
  where id = target_entry_id
  for update;

  if not found then
    raise exception 'Ledger entry not found';
  end if;

  if exists (select 1 from public.wallet_ledger_entries where reversal_of = target_entry_id) then
    raise exception 'Ledger entry already reversed';
  end if;

  reversal_direction := case when original.direction = 'credit' then 'debit' else 'credit' end;

  if reversal_direction = 'debit' and app_private.wallet_balance_cents(original.wallet_account_id) < original.amount_cents then
    raise exception 'Insufficient wallet balance for reversal';
  end if;

  reversal_id := app_private.apply_wallet_entry(
    original.wallet_account_id,
    original.amount_cents,
    reversal_direction,
    'reversal',
    'wallet-reversal:' || target_entry_id,
    coalesce(nullif(trim(reason), ''), 'Wallet ledger reversal'),
    original.beneficiary_id
  );

  update public.wallet_ledger_entries
  set reversal_of = original.id
  where id = reversal_id;

  return reversal_id;
end;
$$;

drop policy if exists payments_owner_or_finance_read on public.payments;
create policy payments_owner_wallet_or_finance_read
on public.payments
for select
to authenticated
using (
  payer_id = auth.uid()
  or beneficiary_id = auth.uid()
  or app_private.has_permission('finance.read')
  or app_private.has_permission('wallet.read')
);

grant select on public.wallet_accounts to authenticated;
grant select on public.wallet_ledger_entries to authenticated;
grant select on public.wallet_balances to authenticated;
grant select on public.payments to authenticated;

revoke all on function public.ensure_wallet_account(uuid, uuid, text) from public;
revoke all on function public.create_wallet_top_up(uuid, int, text, text) from public;
revoke all on function public.settle_wallet_top_up(uuid, text, text, text) from public;
revoke all on function public.adjust_wallet_balance(uuid, int, text, text, text, text, uuid) from public;
revoke all on function public.reverse_wallet_ledger_entry(uuid, text) from public;

grant execute on function public.ensure_wallet_account(uuid, uuid, text) to authenticated;
grant execute on function public.create_wallet_top_up(uuid, int, text, text) to authenticated;
grant execute on function public.settle_wallet_top_up(uuid, text, text, text) to authenticated;
grant execute on function public.adjust_wallet_balance(uuid, int, text, text, text, text, uuid) to authenticated;
grant execute on function public.reverse_wallet_ledger_entry(uuid, text) to authenticated;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
cross join public.permissions p
where r.key = 'treasurer'
  and p.key = 'wallet.adjust'
on conflict do nothing;
