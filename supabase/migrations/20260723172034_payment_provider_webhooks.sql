-- Payment provider catalogue and idempotent provider webhook processing.

create table if not exists public.payment_providers (
  provider_key text primary key,
  display_name text not null,
  provider_type text not null check (provider_type in ('manual','stripe','square','custom')),
  is_active boolean not null default true,
  supports_webhooks boolean not null default false,
  webhook_secret_ref text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.payment_webhook_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_event_id text not null,
  event_type text not null,
  payment_id uuid references public.payments(id) on delete set null,
  provider_payment_id text,
  status text not null default 'received' check (status in ('received','processed','ignored','failed')),
  payload jsonb not null default '{}'::jsonb,
  error_message text,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  unique (provider, provider_event_id)
);

create index if not exists payment_providers_active_idx
on public.payment_providers (is_active, provider_type);

create index if not exists payment_webhook_events_received_idx
on public.payment_webhook_events (received_at desc);

create index if not exists payment_webhook_events_payment_idx
on public.payment_webhook_events (payment_id, received_at desc)
where payment_id is not null;

create index if not exists payment_webhook_events_provider_payment_idx
on public.payment_webhook_events (provider, provider_payment_id)
where provider_payment_id is not null;

alter table public.payment_providers enable row level security;
alter table public.payment_webhook_events enable row level security;

drop policy if exists payment_providers_finance_read on public.payment_providers;
create policy payment_providers_finance_read
on public.payment_providers
for select
to authenticated
using (app_private.has_permission('finance.read') or app_private.has_permission('wallet.read'));

drop policy if exists payment_webhook_events_finance_read on public.payment_webhook_events;
create policy payment_webhook_events_finance_read
on public.payment_webhook_events
for select
to authenticated
using (app_private.has_permission('finance.read') or app_private.has_permission('wallet.read'));

insert into public.payment_providers (provider_key, display_name, provider_type, supports_webhooks, webhook_secret_ref)
values
  ('manual', 'Manual settlement', 'manual', false, null),
  ('stripe', 'Stripe', 'stripe', true, 'PAYMENT_WEBHOOK_SECRET'),
  ('square', 'Square', 'square', true, 'PAYMENT_WEBHOOK_SECRET')
on conflict (provider_key) do update
set display_name = excluded.display_name,
    provider_type = excluded.provider_type,
    supports_webhooks = excluded.supports_webhooks,
    webhook_secret_ref = excluded.webhook_secret_ref,
    updated_at = now();

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

  safe_provider := lower(coalesce(nullif(trim(provider), ''), 'manual'));
  safe_key := coalesce(nullif(trim(idempotency_key), ''), 'wallet-top-up:' || target_wallet_id || ':' || auth.uid() || ':' || gen_random_uuid());

  insert into public.payments (
    provider,
    payer_id,
    beneficiary_id,
    amount_cents,
    currency,
    status,
    idempotency_key,
    metadata
  )
  values (
    safe_provider,
    auth.uid(),
    coalesce(wallet_row.owner_id, auth.uid()),
    top_up_amount_cents,
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

create or replace function public.process_payment_webhook(
  provider text,
  provider_event_id text,
  event_type text,
  provider_payment_ref text default null,
  target_payment_id uuid default null,
  target_status text default null,
  event_payload jsonb default '{}'::jsonb
)
returns table (
  event_id uuid,
  event_status text,
  payment_id uuid,
  payment_status text,
  already_processed boolean
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  safe_provider text;
  safe_event_id text;
  safe_event_type text;
  safe_target_status text;
  event_row public.payment_webhook_events%rowtype;
  payment_row public.payments%rowtype;
  old_payment public.payments%rowtype;
  wallet_id uuid;
  ledger_entry_id uuid;
begin
  if current_role <> 'service_role' and auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  safe_provider := lower(coalesce(nullif(trim(provider), ''), ''));
  safe_event_id := nullif(trim(provider_event_id), '');
  safe_event_type := coalesce(nullif(trim(event_type), ''), 'payment.updated');
  safe_target_status := lower(coalesce(nullif(trim(target_status), ''), ''));

  if safe_provider = '' or safe_event_id is null then
    raise exception 'Provider and provider event id are required';
  end if;

  if safe_target_status not in ('succeeded','failed','cancelled') then
    raise exception 'Invalid payment status';
  end if;

  insert into public.payment_providers (provider_key, display_name, provider_type, supports_webhooks)
  values (safe_provider, initcap(safe_provider), 'custom', true)
  on conflict (provider_key) do nothing;

  insert into public.payment_webhook_events (
    provider,
    provider_event_id,
    event_type,
    payment_id,
    provider_payment_id,
    status,
    payload
  )
  values (
    safe_provider,
    safe_event_id,
    safe_event_type,
    target_payment_id,
    nullif(trim(provider_payment_ref), ''),
    'received',
    coalesce(event_payload, '{}'::jsonb)
  )
  on conflict (provider, provider_event_id) do update
    set payload = public.payment_webhook_events.payload,
        received_at = public.payment_webhook_events.received_at
  returning * into event_row;

  if event_row.status = 'processed' then
    return query
    select event_row.id, event_row.status, event_row.payment_id, (
      select p.status
      from public.payments p
      where p.id = event_row.payment_id
    ), true;
    return;
  end if;

  select *
  into payment_row
  from public.payments p
  where p.id = target_payment_id
    or (
      target_payment_id is null
      and p.provider = safe_provider
      and p.provider_payment_id = nullif(trim(provider_payment_ref), '')
    )
  order by p.created_at desc
  limit 1
  for update;

  if not found then
    update public.payment_webhook_events
    set status = 'ignored',
        error_message = 'Payment not found',
        processed_at = now()
    where id = event_row.id
    returning * into event_row;

    return query select event_row.id, event_row.status, null::uuid, null::text, false;
    return;
  end if;

  old_payment := payment_row;

  if payment_row.status in ('failed','cancelled','refunded','partially_refunded') and payment_row.status <> safe_target_status then
    update public.payment_webhook_events
    set payment_id = payment_row.id,
        status = 'ignored',
        error_message = 'Payment is already closed',
        processed_at = now()
    where id = event_row.id
    returning * into event_row;

    return query select event_row.id, event_row.status, payment_row.id, payment_row.status, false;
    return;
  end if;

  update public.payments
  set status = safe_target_status,
      provider_payment_id = coalesce(nullif(trim(provider_payment_ref), ''), payments.provider_payment_id),
      settled_at = case when safe_target_status = 'succeeded' then coalesce(payments.settled_at, now()) else payments.settled_at end,
      metadata = payments.metadata || jsonb_build_object('last_webhook_event_id', event_row.id, 'last_webhook_event_type', safe_event_type),
      updated_at = now()
  where id = payment_row.id
  returning * into payment_row;

  if safe_target_status = 'succeeded' and payment_row.metadata->>'purpose' = 'wallet_top_up' then
    wallet_id := (payment_row.metadata->>'wallet_account_id')::uuid;

    insert into public.wallet_ledger_entries (
      wallet_account_id,
      amount_cents,
      direction,
      transaction_type,
      related_entity_type,
      related_entity_id,
      idempotency_key,
      description,
      initiating_user_id,
      beneficiary_id
    )
    values (
      wallet_id,
      payment_row.amount_cents,
      'credit',
      'top_up',
      'payment',
      payment_row.id,
      'wallet-top-up-payment:' || payment_row.id,
      'Wallet top-up settled by payment webhook',
      null,
      payment_row.beneficiary_id
    )
    on conflict (wallet_account_id, idempotency_key) do update
      set idempotency_key = excluded.idempotency_key
    returning id into ledger_entry_id;
  end if;

  update public.payment_webhook_events
  set payment_id = payment_row.id,
      provider_payment_id = coalesce(nullif(trim(provider_payment_ref), ''), payment_webhook_events.provider_payment_id),
      status = 'processed',
      error_message = null,
      processed_at = now()
  where id = event_row.id
  returning * into event_row;

  perform app_private.write_audit_log(
    'payment.webhook_processed',
    'payment',
    payment_row.id,
    to_jsonb(old_payment),
    to_jsonb(payment_row) || jsonb_build_object('webhook_event_id', event_row.id, 'ledger_entry_id', ledger_entry_id),
    safe_event_type
  );

  return query select event_row.id, event_row.status, payment_row.id, payment_row.status, false;
end;
$$;

grant select on public.payment_providers to authenticated;
grant select on public.payment_webhook_events to authenticated;

revoke all on function public.process_payment_webhook(text, text, text, text, uuid, text, jsonb) from public;
grant execute on function public.process_payment_webhook(text, text, text, text, uuid, text, jsonb) to service_role;

revoke all on function public.create_wallet_top_up(uuid, int, text, text) from public;
grant execute on function public.create_wallet_top_up(uuid, int, text, text) to authenticated;
