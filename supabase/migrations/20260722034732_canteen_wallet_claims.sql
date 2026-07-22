-- Member-visible voucher codes and staff claim access for the canteen workflow.

alter table public.voucher_issuances
add column if not exists redemption_code text unique;

comment on column public.voucher_issuances.redemption_code is
  'Member-visible voucher code used to render wallet QR codes. token_hash remains the value checked during redemption.';

drop policy if exists vouchers_staff_redeem_read on public.voucher_issuances;
create policy vouchers_staff_redeem_read
on public.voucher_issuances
for select
to authenticated
using (app_private.has_permission('canteen.vouchers.redeem'));

drop policy if exists voucher_redemptions_staff_create on public.voucher_redemptions;
create policy voucher_redemptions_staff_create
on public.voucher_redemptions
for insert
to authenticated
with check (redeemed_by = auth.uid() and app_private.has_permission('canteen.vouchers.redeem'));

drop policy if exists order_history_staff_create on public.order_status_history;
create policy order_history_staff_create
on public.order_status_history
for insert
to authenticated
with check (changed_by = auth.uid() and app_private.has_permission('canteen.orders.manage'));
