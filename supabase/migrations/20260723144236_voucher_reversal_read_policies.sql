-- Allow voucher reversal operators to review claim and reversal history.

drop policy if exists voucher_redemptions_staff_read on public.voucher_redemptions;
create policy voucher_redemptions_staff_read
on public.voucher_redemptions
for select
to authenticated
using (
  redeemed_by = auth.uid()
  or app_private.has_permission('canteen.vouchers.manage')
  or app_private.has_permission('canteen.vouchers.reverse')
);

drop policy if exists voucher_reversals_manager_read on public.voucher_reversals;
create policy voucher_reversals_manager_read
on public.voucher_reversals
for select
to authenticated
using (
  app_private.has_permission('canteen.vouchers.manage')
  or app_private.has_permission('canteen.vouchers.reverse')
);

grant select on public.voucher_redemptions to authenticated;
grant select on public.voucher_reversals to authenticated;
