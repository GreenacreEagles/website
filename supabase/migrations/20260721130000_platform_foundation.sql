-- Greenacre Eagles FC platform foundation.
-- This migration creates the database spine for the public site, member portal,
-- admin portal, commerce, vouchers, teams, volunteers, reporting, and audit.

create extension if not exists pgcrypto with schema extensions;

create schema if not exists app_private;

create or replace function app_private.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function app_private.current_user_id()
returns uuid
language sql
stable
as $$
  select auth.uid();
$$;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  preferred_name text,
  mobile text,
  date_of_birth date,
  relationship_to_club text,
  emergency_contact_name text,
  emergency_contact_phone text,
  communication_email boolean not null default true,
  communication_sms boolean not null default false,
  terms_accepted_at timestamptz,
  privacy_accepted_at timestamptz,
  onboarding_completed_at timestamptz,
  account_status text not null default 'active' check (account_status in ('active','suspended','deleted_requested')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function app_private.set_updated_at();

create or replace function app_private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''))
  on conflict (id) do nothing;

  insert into public.user_role_assignments (user_id, role_id, status, reason)
  select new.id, r.id, 'active', 'Automatic general-user provisioning'
  from public.roles r
  where r.key = 'general_user'
    and not exists (
      select 1
      from public.user_role_assignments ura
      where ura.user_id = new.id
        and ura.role_id = r.id
        and ura.status = 'active'
    );

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function app_private.handle_new_user();

create table public.seasons (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  year int not null check (year between 2000 and 2100),
  starts_on date not null,
  ends_on date not null,
  status text not null default 'draft' check (status in ('draft','active','completed','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_on >= starts_on)
);

create table public.venues (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  address text,
  suburb text,
  state text not null default 'NSW',
  postcode text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.competitions (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  external_url text,
  season_id uuid references public.seasons(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.age_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  min_age int,
  max_age int,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (min_age is null or min_age >= 0),
  check (max_age is null or max_age >= min_age)
);

create table public.teams (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete restrict,
  competition_id uuid references public.competitions(id) on delete set null,
  age_group_id uuid references public.age_groups(id) on delete set null,
  name text not null,
  division text,
  colour text,
  home_venue_id uuid references public.venues(id) on delete set null,
  training_venue_id uuid references public.venues(id) on delete set null,
  external_fixture_url text,
  status text not null default 'active' check (status in ('draft','active','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (season_id, name)
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  key text not null unique check (key ~ '^[a-z0-9_.-]+$'),
  name text not null,
  description text,
  is_system boolean not null default false,
  is_sensitive boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.permissions (
  id uuid primary key default gen_random_uuid(),
  key text not null unique check (key = '*' or key ~ '^[a-z0-9_.-]+$'),
  name text not null,
  description text,
  created_at timestamptz not null default now()
);

create table public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (role_id, permission_id)
);

create table public.user_role_assignments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete restrict,
  team_id uuid references public.teams(id) on delete cascade,
  season_id uuid references public.seasons(id) on delete cascade,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  status text not null default 'active' check (status in ('active','pending','suspended','expired','revoked')),
  reason text,
  assigned_by uuid references public.profiles(id) on delete set null,
  revoked_by uuid references public.profiles(id) on delete set null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at)
);

create index user_role_assignments_active_idx on public.user_role_assignments (user_id, status, team_id, season_id);

create or replace function app_private.has_permission(
  permission_key text,
  target_team_id uuid default null,
  target_season_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1
    from public.user_role_assignments ura
    join public.role_permissions rp on rp.role_id = ura.role_id
    join public.permissions p on p.id = rp.permission_id
    where ura.user_id = auth.uid()
      and ura.status = 'active'
      and ura.starts_at <= now()
      and (ura.ends_at is null or ura.ends_at > now())
      and (p.key = permission_key or p.key = '*')
      and (target_team_id is null or ura.team_id is null or ura.team_id = target_team_id)
      and (target_season_id is null or ura.season_id is null or ura.season_id = target_season_id)
  );
$$;

create or replace function public.has_permission(
  permission_key text,
  target_team_id uuid default null,
  target_season_id uuid default null
)
returns boolean
language sql
stable
security invoker
set search_path = public, extensions
as $$
  select app_private.has_permission(permission_key, target_team_id, target_season_id);
$$;

create or replace function app_private.can_assign_role(target_role_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select case
    when exists (
      select 1
      from public.roles r
      where r.id = target_role_id
        and r.key = 'super_administrator'
    )
    then app_private.has_permission('*')
    else app_private.has_permission('roles.assign')
  end;
$$;

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  before_state jsonb,
  after_state jsonb,
  reason text,
  correlation_id text,
  ip_address inet,
  user_agent text,
  created_at timestamptz not null default now()
);

create index audit_logs_entity_idx on public.audit_logs (entity_type, entity_id, created_at desc);
create index audit_logs_actor_idx on public.audit_logs (actor_id, created_at desc);

create or replace function app_private.write_audit_log(
  action text,
  entity_type text,
  entity_id uuid default null,
  before_state jsonb default null,
  after_state jsonb default null,
  reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  audit_id uuid;
begin
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, before_state, after_state, reason)
  values (auth.uid(), action, entity_type, entity_id, before_state, after_state, reason)
  returning id into audit_id;
  return audit_id;
end;
$$;

create table public.role_assignment_history (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid references public.user_role_assignments(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null check (action in ('created','updated','revoked','expired')),
  before_state jsonb,
  after_state jsonb,
  reason text,
  created_at timestamptz not null default now()
);

create or replace function app_private.record_role_assignment_history()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.role_assignment_history (assignment_id, actor_id, action, after_state, reason)
    values (new.id, auth.uid(), 'created', to_jsonb(new), new.reason);
    return new;
  elsif tg_op = 'UPDATE' then
    insert into public.role_assignment_history (assignment_id, actor_id, action, before_state, after_state, reason)
    values (
      new.id,
      auth.uid(),
      case when new.status = 'revoked' and old.status <> 'revoked' then 'revoked' else 'updated' end,
      to_jsonb(old),
      to_jsonb(new),
      coalesce(new.reason, old.reason)
    );
    return new;
  end if;
  return new;
end;
$$;

create trigger user_role_assignments_history
after insert or update on public.user_role_assignments
for each row execute function app_private.record_role_assignment_history();

create table public.role_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  requested_role_id uuid references public.roles(id) on delete set null,
  team_id uuid references public.teams(id) on delete set null,
  season_id uuid references public.seasons(id) on delete set null,
  relationship_note text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.families (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.family_members (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  relationship text not null,
  is_primary_guardian boolean not null default false,
  can_manage boolean not null default false,
  can_spend boolean not null default false,
  spending_limit_cents int check (spending_limit_cents is null or spending_limit_cents >= 0),
  status text not null default 'active' check (status in ('pending','active','revoked')),
  invited_by uuid references public.profiles(id) on delete set null,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (family_id, user_id)
);

create table public.player_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  season_id uuid not null references public.seasons(id) on delete restrict,
  registration_status text not null default 'not_started' check (registration_status in ('not_started','pending','registered','transferred','withdrawn')),
  external_registration_ref text,
  photo_consent boolean,
  code_of_conduct_accepted_at timestamptz,
  medical_notes text,
  support_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, season_id)
);

create table public.team_players (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  player_id uuid not null references public.player_records(id) on delete cascade,
  squad_number int,
  starts_on date,
  ends_on date,
  status text not null default 'active' check (status in ('active','inactive','left')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (team_id, player_id)
);

create table public.team_staff (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  staff_role text not null check (staff_role in ('coach','assistant_coach','team_manager','trainer')),
  starts_on date,
  ends_on date,
  status text not null default 'active' check (status in ('active','inactive','left')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (team_id, user_id, staff_role)
);

create table public.training_sessions (
  id uuid primary key default gen_random_uuid(),
  team_id uuid references public.teams(id) on delete cascade,
  venue_id uuid references public.venues(id) on delete set null,
  starts_at timestamptz not null,
  ends_at timestamptz,
  notes text,
  status text not null default 'scheduled' check (status in ('scheduled','cancelled','completed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.fixtures (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete restrict,
  team_id uuid not null references public.teams(id) on delete cascade,
  competition_id uuid references public.competitions(id) on delete set null,
  round text,
  opponent text not null,
  venue_id uuid references public.venues(id) on delete set null,
  starts_at timestamptz not null,
  home_away text check (home_away in ('home','away','neutral')),
  status text not null default 'scheduled' check (status in ('scheduled','postponed','cancelled','completed')),
  external_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.match_reports (
  id uuid primary key default gen_random_uuid(),
  fixture_id uuid references public.fixtures(id) on delete set null,
  team_id uuid not null references public.teams(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete restrict,
  final_score_for int,
  final_score_against int,
  result text check (result in ('win','draw','loss','abandoned')),
  highlights text,
  improvement_notes text,
  conduct_issues text,
  injury_notes text,
  private_notes text,
  status text not null default 'draft' check (status in ('draft','submitted','changes_requested','reviewed','closed')),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  reviewer_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.content_articles (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  slug text not null unique,
  summary text,
  body jsonb not null default '{}'::jsonb,
  seo_title text,
  seo_description text,
  featured_image_url text,
  author_id uuid references public.profiles(id) on delete set null,
  workflow_status text not null default 'draft' check (workflow_status in ('draft','in_review','scheduled','published','archived')),
  publish_at timestamptz,
  category text,
  tags text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.club_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  message text not null,
  audience text not null default 'public',
  priority int not null default 0,
  starts_at timestamptz,
  ends_at timestamptz,
  status text not null default 'draft' check (status in ('draft','published','archived')),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.sponsors (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  logo_url text,
  website_url text,
  tier text,
  description text,
  starts_on date,
  ends_on date,
  display_locations text[] not null default '{}',
  display_priority int not null default 0,
  contact_name text,
  contact_email text,
  internal_notes text,
  status text not null default 'active' check (status in ('active','inactive','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.canteen_venues (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid references public.venues(id) on delete set null,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.canteen_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  display_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.canteen_products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references public.canteen_categories(id) on delete set null,
  name text not null,
  description text,
  image_url text,
  price_cents int not null check (price_cents >= 0),
  gst_cents int not null default 0 check (gst_cents >= 0),
  dietary_info text[] not null default '{}',
  allergen_info text[] not null default '{}',
  preparation_minutes int not null default 5 check (preparation_minutes >= 0),
  max_quantity_per_order int check (max_quantity_per_order is null or max_quantity_per_order > 0),
  display_order int not null default 0,
  is_active boolean not null default true,
  is_sold_out boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.canteen_products(id) on delete cascade,
  movement_type text not null check (movement_type in ('stock_in','stock_out','reserve','release','adjustment','sale','waste')),
  quantity int not null,
  reason text,
  related_entity_type text,
  related_entity_id uuid,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.canteen_orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique,
  venue_id uuid references public.canteen_venues(id) on delete set null,
  customer_id uuid not null references public.profiles(id) on delete restrict,
  recipient_id uuid references public.profiles(id) on delete set null,
  pickup_window_start timestamptz,
  pickup_window_end timestamptz,
  subtotal_cents int not null default 0 check (subtotal_cents >= 0),
  discount_cents int not null default 0 check (discount_cents >= 0),
  total_cents int not null default 0 check (total_cents >= 0),
  payment_status text not null default 'unpaid' check (payment_status in ('unpaid','awaiting_payment','paid','partially_refunded','refunded')),
  order_status text not null default 'draft' check (order_status in ('draft','awaiting_payment','paid','accepted','preparing','ready_for_pickup','collected','cancelled','refunded','partially_refunded','expired')),
  qr_token_hash text,
  special_instructions text,
  idempotency_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.canteen_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.canteen_orders(id) on delete cascade,
  product_id uuid references public.canteen_products(id) on delete set null,
  product_name_snapshot text not null,
  unit_price_cents_snapshot int not null check (unit_price_cents_snapshot >= 0),
  quantity int not null check (quantity > 0),
  options_snapshot jsonb not null default '{}'::jsonb,
  allergen_snapshot text[] not null default '{}',
  line_total_cents int not null check (line_total_cents >= 0),
  created_at timestamptz not null default now()
);

create table public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.canteen_orders(id) on delete cascade,
  old_status text,
  new_status text not null,
  changed_by uuid references public.profiles(id) on delete set null,
  reason text,
  created_at timestamptz not null default now()
);

create table public.voucher_issuances (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  beneficiary_id uuid references public.profiles(id) on delete set null,
  family_id uuid references public.families(id) on delete set null,
  team_id uuid references public.teams(id) on delete set null,
  issued_by uuid references public.profiles(id) on delete set null,
  issue_reason text,
  voucher_type text not null check (voucher_type in ('fixed_amount','specific_product','category','meal_deal','declining_balance')),
  original_value_cents int not null default 0 check (original_value_cents >= 0),
  remaining_value_cents int not null default 0 check (remaining_value_cents >= 0),
  allowed_product_ids uuid[] not null default '{}',
  allowed_category_ids uuid[] not null default '{}',
  venue_id uuid references public.canteen_venues(id) on delete set null,
  valid_from timestamptz not null default now(),
  expires_at timestamptz,
  redemption_limit int not null default 1 check (redemption_limit > 0),
  redemption_count int not null default 0 check (redemption_count >= 0),
  status text not null default 'active' check (status in ('draft','active','claimed','expired','revoked')),
  claimed_at timestamptz,
  revoked_by uuid references public.profiles(id) on delete set null,
  revoked_at timestamptz,
  revocation_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (remaining_value_cents <= original_value_cents),
  check (expires_at is null or expires_at > valid_from)
);

create table public.voucher_redemptions (
  id uuid primary key default gen_random_uuid(),
  voucher_id uuid not null references public.voucher_issuances(id) on delete restrict,
  redeemed_by uuid not null references public.profiles(id) on delete restrict,
  venue_id uuid references public.canteen_venues(id) on delete set null,
  order_id uuid references public.canteen_orders(id) on delete set null,
  amount_cents int not null check (amount_cents > 0),
  status text not null default 'completed' check (status in ('completed','reversed')),
  device_label text,
  created_at timestamptz not null default now()
);

create table public.voucher_reversals (
  id uuid primary key default gen_random_uuid(),
  redemption_id uuid not null references public.voucher_redemptions(id) on delete restrict,
  authorised_by uuid not null references public.profiles(id) on delete restrict,
  reason text not null,
  amount_cents int not null check (amount_cents > 0),
  created_at timestamptz not null default now()
);

create table public.wallet_accounts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references public.profiles(id) on delete cascade,
  family_id uuid references public.families(id) on delete cascade,
  account_type text not null default 'user' check (account_type in ('user','family','club')),
  status text not null default 'active' check (status in ('active','frozen','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (owner_id is not null or family_id is not null)
);

create table public.wallet_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  wallet_account_id uuid not null references public.wallet_accounts(id) on delete restrict,
  amount_cents int not null,
  direction text not null check (direction in ('credit','debit')),
  transaction_type text not null,
  related_entity_type text,
  related_entity_id uuid,
  initiating_user_id uuid references public.profiles(id) on delete set null,
  beneficiary_id uuid references public.profiles(id) on delete set null,
  description text,
  idempotency_key text not null,
  reversal_of uuid references public.wallet_ledger_entries(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (wallet_account_id, idempotency_key)
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_payment_id text,
  payer_id uuid references public.profiles(id) on delete set null,
  beneficiary_id uuid references public.profiles(id) on delete set null,
  amount_cents int not null check (amount_cents >= 0),
  currency text not null default 'AUD',
  status text not null default 'created' check (status in ('created','requires_action','succeeded','failed','cancelled','refunded','partially_refunded')),
  idempotency_key text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.merchandise_products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  category text,
  image_url text,
  featured boolean not null default false,
  status text not null default 'active' check (status in ('draft','active','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.merchandise_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.merchandise_products(id) on delete cascade,
  sku text unique,
  size text,
  colour text,
  price_cents int not null check (price_cents >= 0),
  sale_price_cents int check (sale_price_cents is null or sale_price_cents >= 0),
  stock_quantity int not null default 0 check (stock_quantity >= 0),
  low_stock_threshold int not null default 0 check (low_stock_threshold >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.merchandise_orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique,
  customer_id uuid not null references public.profiles(id) on delete restrict,
  total_cents int not null default 0 check (total_cents >= 0),
  status text not null default 'awaiting_payment' check (status in ('awaiting_payment','paid','processing','awaiting_stock','ready_for_pickup','shipped','collected','completed','cancelled','refunded','partially_refunded')),
  pickup_or_delivery text not null default 'pickup' check (pickup_or_delivery in ('pickup','delivery')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.club_events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  slug text not null unique,
  description text,
  image_url text,
  venue_id uuid references public.venues(id) on delete set null,
  starts_at timestamptz not null,
  ends_at timestamptz,
  capacity int check (capacity is null or capacity > 0),
  registration_opens_at timestamptz,
  registration_closes_at timestamptz,
  price_cents int not null default 0 check (price_cents >= 0),
  visibility text not null default 'public' check (visibility in ('public','members','private')),
  status text not null default 'draft' check (status in ('draft','published','cancelled','completed','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.event_registrations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.club_events(id) on delete cascade,
  attendee_id uuid references public.profiles(id) on delete set null,
  registered_by uuid references public.profiles(id) on delete set null,
  status text not null default 'interest' check (status in ('interest','confirmed','waitlisted','cancelled','attended','no_show')),
  answers jsonb not null default '{}'::jsonb,
  checked_in_at timestamptz,
  checked_in_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_id, attendee_id)
);

create table public.volunteer_opportunities (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  opportunity_type text not null,
  required_permission text,
  status text not null default 'active' check (status in ('active','paused','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.volunteer_shifts (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references public.volunteer_opportunities(id) on delete cascade,
  venue_id uuid references public.venues(id) on delete set null,
  starts_at timestamptz not null,
  ends_at timestamptz,
  capacity int not null default 1 check (capacity > 0),
  status text not null default 'open' check (status in ('open','filled','cancelled','completed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.volunteer_assignments (
  id uuid primary key default gen_random_uuid(),
  shift_id uuid not null references public.volunteer_shifts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'assigned' check (status in ('interested','assigned','checked_in','completed','cancelled','replacement_requested')),
  checked_in_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shift_id, user_id)
);

create table public.coaching_resources (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  resource_type text not null check (resource_type in ('drill','session_plan','program','policy','video','document','external_link')),
  summary text,
  body jsonb not null default '{}'::jsonb,
  age_group_tags text[] not null default '{}',
  skill_level_tags text[] not null default '{}',
  duration_minutes int check (duration_minutes is null or duration_minutes >= 0),
  equipment_required text[] not null default '{}',
  visibility text not null default 'coaches' check (visibility in ('public','coaches','team_staff','admins')),
  status text not null default 'draft' check (status in ('draft','published','archived')),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.file_records (
  id uuid primary key default gen_random_uuid(),
  bucket text not null,
  object_path text not null,
  owner_id uuid references public.profiles(id) on delete set null,
  related_entity_type text,
  related_entity_id uuid,
  visibility text not null default 'private' check (visibility in ('public','private','role_restricted')),
  mime_type text,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  created_at timestamptz not null default now(),
  unique (bucket, object_path)
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  related_entity_type text,
  related_entity_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.communication_outbox (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid references public.profiles(id) on delete set null,
  channel text not null check (channel in ('email','sms','in_app')),
  template_key text,
  payload jsonb not null default '{}'::jsonb,
  related_entity_type text,
  related_entity_id uuid,
  status text not null default 'pending' check (status in ('pending','sent','failed','cancelled')),
  failure_reason text,
  scheduled_for timestamptz not null default now(),
  sent_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.system_settings (
  key text primary key,
  value jsonb not null,
  description text,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

create or replace function app_private.redeem_voucher(
  redemption_token text,
  redeem_venue_id uuid,
  redeem_amount_cents int,
  redeem_order_id uuid default null,
  device_label text default null
)
returns table (
  redemption_id uuid,
  voucher_id uuid,
  remaining_value_cents int,
  result text
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v public.voucher_issuances%rowtype;
  new_redemption_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not app_private.has_permission('canteen.vouchers.redeem', null, null) then
    raise exception 'Worker not authorised';
  end if;

  if redeem_amount_cents <= 0 then
    raise exception 'Invalid redemption amount';
  end if;

  select *
  into v
  from public.voucher_issuances
  where token_hash = encode(extensions.digest(redemption_token, 'sha256'), 'hex')
  for update;

  if not found then
    raise exception 'Invalid token';
  end if;

  if v.status <> 'active' then
    raise exception 'Voucher not active';
  end if;

  if v.valid_from > now() then
    raise exception 'Voucher not active';
  end if;

  if v.expires_at is not null and v.expires_at <= now() then
    raise exception 'Expired voucher';
  end if;

  if v.venue_id is not null and v.venue_id <> redeem_venue_id then
    raise exception 'Wrong venue';
  end if;

  if v.redemption_count >= v.redemption_limit then
    raise exception 'Already redeemed';
  end if;

  if v.remaining_value_cents < redeem_amount_cents then
    raise exception 'Insufficient balance';
  end if;

  update public.voucher_issuances
  set remaining_value_cents = remaining_value_cents - redeem_amount_cents,
      redemption_count = redemption_count + 1,
      claimed_at = coalesce(claimed_at, now()),
      status = case
        when redemption_count + 1 >= redemption_limit or remaining_value_cents - redeem_amount_cents = 0 then 'claimed'
        else status
      end,
      updated_at = now()
  where id = v.id;

  insert into public.voucher_redemptions (voucher_id, redeemed_by, venue_id, order_id, amount_cents, device_label)
  values (v.id, auth.uid(), redeem_venue_id, redeem_order_id, redeem_amount_cents, device_label)
  returning id into new_redemption_id;

  perform app_private.write_audit_log('voucher.redeemed', 'voucher_issuance', v.id, to_jsonb(v), null, null);

  return query
  select new_redemption_id, v.id, v.remaining_value_cents - redeem_amount_cents, 'redeemed'::text;
end;
$$;

create or replace function public.redeem_voucher(
  redemption_token text,
  redeem_venue_id uuid,
  redeem_amount_cents int,
  redeem_order_id uuid default null,
  device_label text default null
)
returns table (
  redemption_id uuid,
  voucher_id uuid,
  remaining_value_cents int,
  result text
)
language sql
security invoker
set search_path = public, extensions
as $$
  select * from app_private.redeem_voucher(redemption_token, redeem_venue_id, redeem_amount_cents, redeem_order_id, device_label);
$$;

create or replace function app_private.reverse_voucher_redemption(
  target_redemption_id uuid,
  reason text
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  r public.voucher_redemptions%rowtype;
  reversal_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not app_private.has_permission('canteen.vouchers.reverse', null, null) then
    raise exception 'Not authorised';
  end if;

  select * into r
  from public.voucher_redemptions
  where id = target_redemption_id
  for update;

  if not found then
    raise exception 'Redemption not found';
  end if;

  if r.status = 'reversed' then
    raise exception 'Redemption already reversed';
  end if;

  update public.voucher_redemptions
  set status = 'reversed'
  where id = r.id;

  update public.voucher_issuances
  set remaining_value_cents = remaining_value_cents + r.amount_cents,
      redemption_count = greatest(redemption_count - 1, 0),
      status = 'active',
      updated_at = now()
  where id = r.voucher_id;

  insert into public.voucher_reversals (redemption_id, authorised_by, reason, amount_cents)
  values (r.id, auth.uid(), reason, r.amount_cents)
  returning id into reversal_id;

  perform app_private.write_audit_log('voucher.redemption_reversed', 'voucher_redemption', r.id, to_jsonb(r), null, reason);
  return reversal_id;
end;
$$;

create or replace function public.reverse_voucher_redemption(target_redemption_id uuid, reason text)
returns uuid
language sql
security invoker
set search_path = public, extensions
as $$
  select app_private.reverse_voucher_redemption(target_redemption_id, reason);
$$;

create or replace function app_private.apply_wallet_entry(
  wallet_id uuid,
  amount_cents int,
  direction text,
  transaction_type text,
  idempotency_key text,
  description text default null,
  beneficiary_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  entry_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if direction not in ('credit','debit') or amount_cents <= 0 then
    raise exception 'Invalid wallet entry';
  end if;

  if not app_private.has_permission('wallet.adjust', null, null) then
    raise exception 'Not authorised';
  end if;

  insert into public.wallet_ledger_entries (
    wallet_account_id,
    amount_cents,
    direction,
    transaction_type,
    idempotency_key,
    description,
    initiating_user_id,
    beneficiary_id
  )
  values (wallet_id, amount_cents, direction, transaction_type, idempotency_key, description, auth.uid(), beneficiary_id)
  on conflict (wallet_account_id, idempotency_key) do update
    set idempotency_key = excluded.idempotency_key
  returning id into entry_id;

  perform app_private.write_audit_log('wallet.ledger_entry', 'wallet_account', wallet_id, null, jsonb_build_object('entry_id', entry_id), description);
  return entry_id;
end;
$$;

create view public.wallet_balances
with (security_invoker = true)
as
select
  wallet_account_id,
  coalesce(sum(case when direction = 'credit' then amount_cents else -amount_cents end), 0)::int as balance_cents
from public.wallet_ledger_entries
group by wallet_account_id;

-- Updated-at triggers for mutable tables.
do $$
declare
  t text;
begin
  foreach t in array array[
    'seasons','venues','competitions','age_groups','teams','user_role_assignments','role_requests',
    'families','family_members','player_records','team_players','team_staff','training_sessions',
    'fixtures','match_reports','content_articles','club_announcements','sponsors','canteen_venues',
    'canteen_categories','canteen_products','canteen_orders','voucher_issuances','wallet_accounts',
    'payments','merchandise_products','merchandise_variants','merchandise_orders','club_events',
    'event_registrations','volunteer_opportunities','volunteer_shifts','volunteer_assignments',
    'coaching_resources'
  ]
  loop
    execute format('create trigger %I_set_updated_at before update on public.%I for each row execute function app_private.set_updated_at()', t, t);
  end loop;
end;
$$;

-- RLS
alter table public.profiles enable row level security;
alter table public.seasons enable row level security;
alter table public.venues enable row level security;
alter table public.competitions enable row level security;
alter table public.age_groups enable row level security;
alter table public.teams enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_role_assignments enable row level security;
alter table public.audit_logs enable row level security;
alter table public.role_assignment_history enable row level security;
alter table public.role_requests enable row level security;
alter table public.families enable row level security;
alter table public.family_members enable row level security;
alter table public.player_records enable row level security;
alter table public.team_players enable row level security;
alter table public.team_staff enable row level security;
alter table public.training_sessions enable row level security;
alter table public.fixtures enable row level security;
alter table public.match_reports enable row level security;
alter table public.content_articles enable row level security;
alter table public.club_announcements enable row level security;
alter table public.sponsors enable row level security;
alter table public.canteen_venues enable row level security;
alter table public.canteen_categories enable row level security;
alter table public.canteen_products enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.canteen_orders enable row level security;
alter table public.canteen_order_items enable row level security;
alter table public.order_status_history enable row level security;
alter table public.voucher_issuances enable row level security;
alter table public.voucher_redemptions enable row level security;
alter table public.voucher_reversals enable row level security;
alter table public.wallet_accounts enable row level security;
alter table public.wallet_ledger_entries enable row level security;
alter table public.payments enable row level security;
alter table public.merchandise_products enable row level security;
alter table public.merchandise_variants enable row level security;
alter table public.merchandise_orders enable row level security;
alter table public.club_events enable row level security;
alter table public.event_registrations enable row level security;
alter table public.volunteer_opportunities enable row level security;
alter table public.volunteer_shifts enable row level security;
alter table public.volunteer_assignments enable row level security;
alter table public.coaching_resources enable row level security;
alter table public.file_records enable row level security;
alter table public.notifications enable row level security;
alter table public.communication_outbox enable row level security;
alter table public.system_settings enable row level security;

create policy profiles_read_self_or_admin on public.profiles
for select to authenticated
using (id = auth.uid() or app_private.has_permission('users.read'));

create policy profiles_update_self_or_admin on public.profiles
for update to authenticated
using (id = auth.uid() or app_private.has_permission('users.manage'))
with check (id = auth.uid() or app_private.has_permission('users.manage'));

create policy public_read_reference on public.seasons for select to anon, authenticated using (status in ('active','completed'));
create policy public_read_venues on public.venues for select to anon, authenticated using (true);
create policy public_read_competitions on public.competitions for select to anon, authenticated using (true);
create policy public_read_age_groups on public.age_groups for select to anon, authenticated using (true);
create policy public_read_teams on public.teams for select to anon, authenticated using (status = 'active');
create policy admin_manage_club_structure_seasons on public.seasons for all to authenticated using (app_private.has_permission('club_structure.manage')) with check (app_private.has_permission('club_structure.manage'));
create policy admin_manage_club_structure_venues on public.venues for all to authenticated using (app_private.has_permission('club_structure.manage')) with check (app_private.has_permission('club_structure.manage'));
create policy admin_manage_club_structure_competitions on public.competitions for all to authenticated using (app_private.has_permission('club_structure.manage')) with check (app_private.has_permission('club_structure.manage'));
create policy admin_manage_club_structure_age_groups on public.age_groups for all to authenticated using (app_private.has_permission('club_structure.manage')) with check (app_private.has_permission('club_structure.manage'));
create policy admin_manage_club_structure_teams on public.teams for all to authenticated using (app_private.has_permission('club_structure.manage')) with check (app_private.has_permission('club_structure.manage'));

create policy roles_read_assigned_or_admin on public.roles for select to authenticated using (app_private.has_permission('roles.read'));
create policy permissions_read_assigned_or_admin on public.permissions for select to authenticated using (app_private.has_permission('roles.read'));
create policy role_permissions_read_admin on public.role_permissions for select to authenticated using (app_private.has_permission('roles.read'));
create policy role_assignments_read_self_or_admin on public.user_role_assignments for select to authenticated using (user_id = auth.uid() or app_private.has_permission('roles.assign'));
create policy role_assignments_manage_admin on public.user_role_assignments
for all to authenticated
using (app_private.has_permission('roles.assign'))
with check (app_private.can_assign_role(role_id));

create policy role_requests_own_read on public.role_requests for select to authenticated using (requester_id = auth.uid() or app_private.has_permission('roles.review'));
create policy role_requests_create_own on public.role_requests for insert to authenticated with check (requester_id = auth.uid());
create policy role_requests_review on public.role_requests for update to authenticated using (app_private.has_permission('roles.review')) with check (app_private.has_permission('roles.review'));

create policy family_members_read_related on public.family_members
for select to authenticated
using (user_id = auth.uid() or app_private.has_permission('families.manage') or exists (
  select 1 from public.family_members fm
  where fm.family_id = family_members.family_id and fm.user_id = auth.uid() and fm.status = 'active'
));

create policy families_read_related on public.families
for select to authenticated
using (app_private.has_permission('families.manage') or exists (
  select 1 from public.family_members fm
  where fm.family_id = families.id and fm.user_id = auth.uid() and fm.status = 'active'
));

create policy families_manage_admin on public.families for all to authenticated using (app_private.has_permission('families.manage')) with check (app_private.has_permission('families.manage'));
create policy family_members_manage_admin on public.family_members for all to authenticated using (app_private.has_permission('families.manage')) with check (app_private.has_permission('families.manage'));

create policy players_read_self_guardian_coach_admin on public.player_records
for select to authenticated
using (
  user_id = auth.uid()
  or app_private.has_permission('players.manage')
  or exists (
    select 1 from public.family_members child
    join public.family_members guardian on guardian.family_id = child.family_id
    where child.user_id = player_records.user_id
      and guardian.user_id = auth.uid()
      and guardian.can_manage
      and guardian.status = 'active'
      and child.status = 'active'
  )
);

create policy players_manage_registrar on public.player_records for all to authenticated using (app_private.has_permission('players.manage')) with check (app_private.has_permission('players.manage'));

create policy team_staff_read_team on public.team_staff for select to authenticated using (user_id = auth.uid() or app_private.has_permission('teams.manage', team_id));
create policy team_players_read_team_staff on public.team_players for select to authenticated using (app_private.has_permission('teams.read', team_id) or app_private.has_permission('teams.manage', team_id));
create policy team_manage_admin_staff on public.team_staff for all to authenticated using (app_private.has_permission('teams.manage', team_id)) with check (app_private.has_permission('teams.manage', team_id));
create policy team_players_manage_admin on public.team_players for all to authenticated using (app_private.has_permission('teams.manage', team_id)) with check (app_private.has_permission('teams.manage', team_id));

create policy training_read_team on public.training_sessions for select to authenticated using (team_id is null or app_private.has_permission('teams.read', team_id));
create policy fixtures_public_read on public.fixtures for select to anon, authenticated using (true);
create policy match_reports_author_team_admin on public.match_reports for select to authenticated using (author_id = auth.uid() or app_private.has_permission('match_reports.read', team_id));
create policy match_reports_submit on public.match_reports for insert to authenticated with check (author_id = auth.uid() and app_private.has_permission('match_reports.submit', team_id));
create policy match_reports_update_author_or_reviewer on public.match_reports for update to authenticated using (author_id = auth.uid() or app_private.has_permission('match_reports.review')) with check (author_id = auth.uid() or app_private.has_permission('match_reports.review'));

create policy content_public_published on public.content_articles for select to anon, authenticated using (workflow_status = 'published' and (publish_at is null or publish_at <= now()));
create policy content_editor_manage on public.content_articles for all to authenticated using (app_private.has_permission('content.manage')) with check (app_private.has_permission('content.manage'));
create policy announcements_public_published on public.club_announcements for select to anon, authenticated using (status = 'published' and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now()));
create policy announcements_editor_manage on public.club_announcements for all to authenticated using (app_private.has_permission('content.manage')) with check (app_private.has_permission('content.manage'));
create policy sponsors_public_active on public.sponsors for select to anon, authenticated using (status = 'active');
create policy sponsors_manage on public.sponsors for all to authenticated using (app_private.has_permission('sponsors.manage')) with check (app_private.has_permission('sponsors.manage'));

create policy canteen_public_catalog on public.canteen_venues for select to anon, authenticated using (is_active);
create policy canteen_categories_public on public.canteen_categories for select to anon, authenticated using (is_active);
create policy canteen_products_public on public.canteen_products for select to anon, authenticated using (is_active and not is_sold_out);
create policy canteen_manage_venues on public.canteen_venues for all to authenticated using (app_private.has_permission('canteen.manage')) with check (app_private.has_permission('canteen.manage'));
create policy canteen_manage_categories on public.canteen_categories for all to authenticated using (app_private.has_permission('canteen.manage')) with check (app_private.has_permission('canteen.manage'));
create policy canteen_manage_products on public.canteen_products for all to authenticated using (app_private.has_permission('canteen.manage')) with check (app_private.has_permission('canteen.manage'));
create policy inventory_manage on public.inventory_movements for all to authenticated using (app_private.has_permission('canteen.manage')) with check (app_private.has_permission('canteen.manage'));
create policy orders_read_own_or_staff on public.canteen_orders for select to authenticated using (customer_id = auth.uid() or recipient_id = auth.uid() or app_private.has_permission('canteen.orders.manage'));
create policy orders_items_read_own_or_staff on public.canteen_order_items for select to authenticated using (exists (select 1 from public.canteen_orders o where o.id = order_id and (o.customer_id = auth.uid() or o.recipient_id = auth.uid())) or app_private.has_permission('canteen.orders.manage'));
create policy orders_staff_manage on public.canteen_orders for update to authenticated using (app_private.has_permission('canteen.orders.manage')) with check (app_private.has_permission('canteen.orders.manage'));
create policy order_history_staff_read on public.order_status_history for select to authenticated using (app_private.has_permission('canteen.orders.manage'));

create policy vouchers_owner_or_manager_read on public.voucher_issuances for select to authenticated using (beneficiary_id = auth.uid() or app_private.has_permission('canteen.vouchers.manage'));
create policy vouchers_manager_manage on public.voucher_issuances for all to authenticated using (app_private.has_permission('canteen.vouchers.manage')) with check (app_private.has_permission('canteen.vouchers.manage'));
create policy voucher_redemptions_staff_read on public.voucher_redemptions for select to authenticated using (redeemed_by = auth.uid() or app_private.has_permission('canteen.vouchers.manage'));
create policy voucher_reversals_manager_read on public.voucher_reversals for select to authenticated using (app_private.has_permission('canteen.vouchers.manage'));

create policy wallets_owner_or_admin_read on public.wallet_accounts for select to authenticated using (owner_id = auth.uid() or app_private.has_permission('wallet.read'));
create policy ledger_owner_or_admin_read on public.wallet_ledger_entries for select to authenticated using (app_private.has_permission('wallet.read') or exists (select 1 from public.wallet_accounts wa where wa.id = wallet_account_id and wa.owner_id = auth.uid()));
create policy payments_owner_or_finance_read on public.payments for select to authenticated using (payer_id = auth.uid() or beneficiary_id = auth.uid() or app_private.has_permission('finance.read'));

create policy merch_public_products on public.merchandise_products for select to anon, authenticated using (status = 'active');
create policy merch_public_variants on public.merchandise_variants for select to anon, authenticated using (is_active);
create policy merch_manage_products on public.merchandise_products for all to authenticated using (app_private.has_permission('merchandise.manage')) with check (app_private.has_permission('merchandise.manage'));
create policy merch_manage_variants on public.merchandise_variants for all to authenticated using (app_private.has_permission('merchandise.manage')) with check (app_private.has_permission('merchandise.manage'));
create policy merch_orders_own_or_manager on public.merchandise_orders for select to authenticated using (customer_id = auth.uid() or app_private.has_permission('merchandise.manage'));

create policy events_public_published on public.club_events for select to anon, authenticated using (status = 'published' and visibility = 'public');
create policy events_manage on public.club_events for all to authenticated using (app_private.has_permission('events.manage')) with check (app_private.has_permission('events.manage'));
create policy event_regs_own_or_manager on public.event_registrations for select to authenticated using (attendee_id = auth.uid() or registered_by = auth.uid() or app_private.has_permission('events.manage'));
create policy event_regs_create_own on public.event_registrations for insert to authenticated with check (registered_by = auth.uid());

create policy volunteer_public_read on public.volunteer_opportunities for select to authenticated using (status = 'active');
create policy volunteer_shifts_read on public.volunteer_shifts for select to authenticated using (status in ('open','filled'));
create policy volunteer_assignments_own on public.volunteer_assignments for select to authenticated using (user_id = auth.uid() or app_private.has_permission('volunteers.manage'));
create policy volunteer_manage on public.volunteer_opportunities for all to authenticated using (app_private.has_permission('volunteers.manage')) with check (app_private.has_permission('volunteers.manage'));
create policy volunteer_shifts_manage on public.volunteer_shifts for all to authenticated using (app_private.has_permission('volunteers.manage')) with check (app_private.has_permission('volunteers.manage'));
create policy volunteer_assignments_manage on public.volunteer_assignments for all to authenticated using (user_id = auth.uid() or app_private.has_permission('volunteers.manage')) with check (user_id = auth.uid() or app_private.has_permission('volunteers.manage'));

create policy coaching_public_read on public.coaching_resources for select to anon, authenticated using (visibility = 'public' and status = 'published');
create policy coaching_staff_read on public.coaching_resources for select to authenticated using (status = 'published' and (visibility = 'public' or app_private.has_permission('coaching_resources.read')));
create policy coaching_manage on public.coaching_resources for all to authenticated using (app_private.has_permission('coaching_resources.manage')) with check (app_private.has_permission('coaching_resources.manage'));

create policy files_public_read on public.file_records for select to anon, authenticated using (visibility = 'public');
create policy files_owner_or_admin_read on public.file_records for select to authenticated using (owner_id = auth.uid() or app_private.has_permission('files.manage'));
create policy files_manage on public.file_records for all to authenticated using (app_private.has_permission('files.manage')) with check (app_private.has_permission('files.manage'));
create policy notifications_own on public.notifications for select to authenticated using (recipient_id = auth.uid());
create policy communication_admin_read on public.communication_outbox for select to authenticated using (app_private.has_permission('communications.manage'));
create policy audit_admin_read on public.audit_logs for select to authenticated using (app_private.has_permission('audit.read'));
create policy settings_admin_read on public.system_settings for select to authenticated using (app_private.has_permission('settings.manage'));
create policy settings_admin_manage on public.system_settings for all to authenticated using (app_private.has_permission('settings.manage')) with check (app_private.has_permission('settings.manage'));

-- Seed permissions and standard roles. These are production-safe definitions, not fake data.
insert into public.permissions (key, name, description) values
  ('*','All permissions','Super administrator access to every protected operation.'),
  ('users.read','Read users','View user profiles.'),
  ('users.manage','Manage users','Manage user profile status and administrative user data.'),
  ('roles.read','Read roles','View roles and permissions.'),
  ('roles.assign','Assign roles','Assign and revoke user roles except super-admin without elevated procedure.'),
  ('roles.review','Review role requests','Approve or reject user role requests.'),
  ('families.manage','Manage families','Manage family links and guardian relationships.'),
  ('players.manage','Manage players','Manage player records and registration details.'),
  ('club_structure.manage','Manage club structure','Manage seasons, venues, competitions and teams.'),
  ('teams.read','Read assigned teams','Read team information when scoped to a team.'),
  ('teams.manage','Manage assigned teams','Manage team staff, squads and schedules.'),
  ('match_reports.submit','Submit match reports','Submit match reports for assigned teams.'),
  ('match_reports.read','Read match reports','Read private match reports for assigned teams.'),
  ('match_reports.review','Review match reports','Review and close internal match reports.'),
  ('content.manage','Manage content','Create, review, schedule and publish content.'),
  ('sponsors.manage','Manage sponsors','Manage sponsor records.'),
  ('canteen.manage','Manage canteen','Manage canteen products, venues, stock and settings.'),
  ('canteen.orders.manage','Manage canteen orders','Operate live canteen order queues.'),
  ('canteen.vouchers.redeem','Redeem vouchers','Validate and redeem active vouchers.'),
  ('canteen.vouchers.manage','Manage vouchers','Issue, revoke and report on vouchers.'),
  ('canteen.vouchers.reverse','Reverse voucher redemptions','Reverse mistaken voucher redemptions.'),
  ('wallet.read','Read wallets','Read wallet accounts and ledger entries.'),
  ('wallet.adjust','Adjust wallets','Create controlled wallet ledger entries.'),
  ('finance.read','Read finance','Read payments and financial reports.'),
  ('merchandise.manage','Manage merchandise','Manage merchandise products and orders.'),
  ('events.manage','Manage events','Manage events and event registrations.'),
  ('volunteers.manage','Manage volunteers','Manage volunteer shifts and assignments.'),
  ('coaching_resources.read','Read coaching resources','Access restricted coaching resources.'),
  ('coaching_resources.manage','Manage coaching resources','Create and publish coaching resources.'),
  ('files.manage','Manage files','Manage protected file records.'),
  ('communications.manage','Manage communications','Manage communication outbox and notifications.'),
  ('audit.read','Read audit log','View sensitive audit activity.'),
  ('settings.manage','Manage settings','Manage system settings.')
on conflict (key) do update set name = excluded.name, description = excluded.description;

insert into public.roles (key, name, description, is_system, is_sensitive) values
  ('general_user','General user','Default signed-in user with personal portal access only.', true, false),
  ('club_member','Club member','Approved club member.', true, false),
  ('parent_guardian','Parent or guardian','Guardian linked to one or more children.', true, false),
  ('player','Player','Registered player portal access.', true, false),
  ('coach','Coach','Team-scoped coach access.', true, false),
  ('assistant_coach','Assistant coach','Team-scoped assistant coach access.', true, false),
  ('team_manager','Team manager','Team-scoped manager access.', true, false),
  ('canteen_worker','Canteen worker','Can operate order queue and redeem vouchers.', true, false),
  ('canteen_manager','Canteen manager','Can manage canteen catalogue, orders, stock and vouchers.', true, true),
  ('merchandise_manager','Merchandise manager','Can manage merchandise catalogue and orders.', true, true),
  ('event_manager','Event manager','Can manage events and registrations.', true, false),
  ('content_editor','Content editor','Can manage public content and announcements.', true, false),
  ('treasurer','Treasurer or finance officer','Can view financial reports and wallet activity.', true, true),
  ('registrar','Registrar','Can manage registrations and player records.', true, true),
  ('volunteer_coordinator','Volunteer coordinator','Can manage volunteer opportunities and rosters.', true, false),
  ('club_administrator','Club administrator','Broad operational administration without super-admin escalation.', true, true),
  ('super_administrator','Super administrator','Unrestricted platform administration.', true, true)
on conflict (key) do update set name = excluded.name, description = excluded.description, is_sensitive = excluded.is_sensitive;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on
  (r.key = 'super_administrator' and p.key = '*')
  or (r.key = 'club_administrator' and p.key in ('users.read','users.manage','roles.read','roles.assign','roles.review','families.manage','players.manage','club_structure.manage','teams.read','teams.manage','match_reports.read','match_reports.review','content.manage','sponsors.manage','canteen.manage','canteen.orders.manage','canteen.vouchers.manage','canteen.vouchers.reverse','merchandise.manage','events.manage','volunteers.manage','coaching_resources.read','coaching_resources.manage','files.manage','communications.manage','audit.read','settings.manage'))
  or (r.key = 'coach' and p.key in ('teams.read','match_reports.submit','match_reports.read','coaching_resources.read'))
  or (r.key = 'assistant_coach' and p.key in ('teams.read','coaching_resources.read'))
  or (r.key = 'team_manager' and p.key in ('teams.read','match_reports.submit','match_reports.read'))
  or (r.key = 'canteen_worker' and p.key in ('canteen.orders.manage','canteen.vouchers.redeem'))
  or (r.key = 'canteen_manager' and p.key in ('canteen.manage','canteen.orders.manage','canteen.vouchers.redeem','canteen.vouchers.manage','canteen.vouchers.reverse'))
  or (r.key = 'merchandise_manager' and p.key in ('merchandise.manage'))
  or (r.key = 'event_manager' and p.key in ('events.manage'))
  or (r.key = 'content_editor' and p.key in ('content.manage','sponsors.manage'))
  or (r.key = 'treasurer' and p.key in ('wallet.read','finance.read'))
  or (r.key = 'registrar' and p.key in ('players.manage','families.manage'))
  or (r.key = 'volunteer_coordinator' and p.key in ('volunteers.manage'))
on conflict do nothing;

-- Backfill profile and baseline general-user assignment for any existing Auth
-- users. The project currently has no users, but this keeps the migration safe
-- for environments where users are created before the platform schema lands.
insert into public.profiles (id, full_name, created_at, updated_at)
select u.id, coalesce(u.raw_user_meta_data ->> 'full_name', ''), now(), now()
from auth.users u
on conflict (id) do nothing;

insert into public.user_role_assignments (user_id, role_id, status, reason)
select p.id, r.id, 'active', 'Backfilled general-user provisioning'
from public.profiles p
join public.roles r on r.key = 'general_user'
where not exists (
  select 1
  from public.user_role_assignments ura
  where ura.user_id = p.id
    and ura.role_id = r.id
    and ura.status = 'active'
);

create or replace function app_private.bootstrap_super_admin(
  target_user_id uuid,
  bootstrap_reason text
)
returns uuid
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  super_role_id uuid;
  assignment_id uuid;
begin
  if session_user not in ('postgres', 'supabase_admin') and current_user not in ('postgres', 'supabase_admin') then
    raise exception 'Bootstrap must be run by a trusted database administrator';
  end if;

  if bootstrap_reason is null or length(trim(bootstrap_reason)) < 10 then
    raise exception 'A clear bootstrap reason is required';
  end if;

  if exists (
    select 1
    from public.user_role_assignments ura
    join public.roles r on r.id = ura.role_id
    where r.key = 'super_administrator'
      and ura.status = 'active'
      and ura.starts_at <= now()
      and (ura.ends_at is null or ura.ends_at > now())
  ) then
    raise exception 'A super administrator already exists';
  end if;

  if not exists (select 1 from public.profiles where id = target_user_id) then
    raise exception 'Target user profile does not exist';
  end if;

  select id into super_role_id
  from public.roles
  where key = 'super_administrator';

  insert into public.user_role_assignments (user_id, role_id, status, reason)
  values (target_user_id, super_role_id, 'active', bootstrap_reason)
  returning id into assignment_id;

  perform app_private.write_audit_log(
    'roles.bootstrap_super_admin',
    'user_role_assignment',
    assignment_id,
    null,
    jsonb_build_object('user_id', target_user_id, 'role', 'super_administrator'),
    bootstrap_reason
  );

  return assignment_id;
end;
$$;

revoke all on schema app_private from public;
revoke all on all functions in schema app_private from public;
revoke all on all functions in schema public from public;
grant usage on schema public to anon, authenticated;
grant usage on schema app_private to authenticated;
grant execute on function app_private.has_permission(text, uuid, uuid) to authenticated;
grant execute on function app_private.redeem_voucher(text, uuid, int, uuid, text) to authenticated;
grant execute on function app_private.reverse_voucher_redemption(uuid, text) to authenticated;
grant execute on function public.has_permission(text, uuid, uuid) to authenticated;
grant execute on function public.redeem_voucher(text, uuid, int, uuid, text) to authenticated;
grant execute on function public.reverse_voucher_redemption(uuid, text) to authenticated;

grant select on
  public.seasons,
  public.venues,
  public.competitions,
  public.age_groups,
  public.teams,
  public.content_articles,
  public.club_announcements,
  public.sponsors,
  public.canteen_venues,
  public.canteen_categories,
  public.canteen_products,
  public.merchandise_products,
  public.merchandise_variants,
  public.club_events,
  public.coaching_resources,
  public.file_records
to anon;

grant select, insert, update, delete on all tables in schema public to authenticated;
