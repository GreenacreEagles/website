# Administration Portal

The admin portal is separate from the member portal under `/admin/`. Members only see an `Admin` entry point when their effective permissions include an administration permission. Direct admin routes are also protected by server-side guards and Supabase RLS/RPC checks.

## Navigation

- `/admin/`: live operational dashboard.
- `/admin/users/`: user search and profile review.
- `/admin/users/[id]/`: user profile, role history, role assignment and revocation.
- `/admin/roles/`: role and permission catalogue.
- `/admin/teams/`: seasons, competitions, venues, teams, staff assignments, squad visibility, training scheduling and match report review.
- `/admin/players/`: players and family administration foundation.
- `/admin/volunteers/`: volunteer opportunities, shifts and assignments.
- `/admin/canteen/`: catalogue, vouchers and order operations.
- `/admin/merchandise/`: merchandise catalogue and orders.
- `/admin/events/`: event publishing and registrations.
- `/admin/content/`: public content and Resource Guide foundations.
- `/admin/audit/`: audit log.
- `/admin/settings/`: system settings for authorised users.

Removed as separate admin surfaces: role assignments, request review, fixtures and communications. Role assignment happens in the Users section. Role requests are deprecated and historical records remain only for audit continuity.

## Dashboard

The dashboard cards come from live Supabase counts: users, new users, active players, families, teams, volunteer assignments, upcoming events, event registrations, canteen order activity, vouchers, content and audit activity. No fake metrics are used.

## Role Assignment

Administrators assign and revoke roles from `/admin/users/[id]/`. The assignment RPC enforces:

- valid active administrator permission,
- scoped team and season fields where required,
- no normal administrator granting `super_administrator`,
- no self-escalation or self-removal of critical admin access,
- role history and audit records.

Member-driven role or team access requests are disabled in source and by the latest migration revoking request RPC execution from `authenticated`.

## Teams And Match Reports

Administrators manage the club hierarchy from `/admin/teams/`. The page now includes team staff assignment for coaches, assistant coaches, team managers and trainers; active squad visibility from player-team links; internal training-session review; and a match-report review queue.

Coaches and team managers submit reports from the member team page. Report review actions stay in administration and require `match_reports.review`.

## Canteen Operations

Administrators manage canteen venues, categories, products, stock levels and fulfilment modes from `/admin/canteen/`. Products can be normal pickup orders or paid wallet-voucher items with a configurable validity window.

Order state changes run through `public.update_canteen_order_state`, which enforces canteen order permissions, locks the order row, records status history and issues purchased voucher items only after the order is marked paid. Staff use `/portal/canteen-staff/` for the live preparation queue, pickup codes, payment marking, voucher scanning and permission-gated claim reversal. Canteen administrators can review voucher claims and reverse mistaken scans from `/admin/canteen/`.

## Merchandise

Administrators manage merchandise products and stock variants from `/admin/merchandise/`. Member orders run through `public.create_merchandise_order`, which locks the selected variant, snapshots the ordered item and reserves stock atomically.

Merchandise order status changes run through `public.update_merchandise_order_state`. The RPC enforces merchandise-management permission, records order status history, notifies the customer and releases reserved stock when an order is cancelled or refunded.

## Wallet Operations

Members create wallet accounts and manual top-up requests from `/portal/vouchers/`. Top-up requests create `payments` rows with wallet metadata; they do not credit the wallet until an authorised treasurer or wallet operator settles them.

Administrators use `/admin/wallets/` to review pending top-ups, mark them succeeded, failed or cancelled, create member wallets, record controlled credit/debit adjustments and reverse mistaken ledger entries. Settlement and adjustment actions run through wallet RPCs so ledger writes are idempotent and auditable.
