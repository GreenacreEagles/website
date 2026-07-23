# Family And Wallet Controls

## Family Administration

Authorised administrators manage family foundations from `/admin/players/`:

- create family groups,
- link guardians, carers, children, players and dependants,
- set primary guardian, management and spending flags,
- set optional spending limits,
- create player records,
- link player records to teams.

Family links are not self-service. Users can invite another guardian only from an existing family where they already have `can_manage`, `can_spend` or primary guardian status. The invitee must accept from an account matching the invited email.

## Portal Family Area

`/portal/family/` shows:

- the signed-in user's family links,
- linked family members,
- child and family vouchers,
- family wallet balances where RLS permits,
- pending invitations,
- guardian invite form where authorised,
- voucher assignment form for linked children,
- player records for the signed-in user.

## Voucher Assignment

Guardians assign eligible vouchers through `public.assign_voucher_to_family_member()`, which delegates protected writes to `app_private.assign_voucher_to_family_member()`.

The function verifies:

- authenticated caller,
- voucher exists and is active,
- voucher has remaining value,
- voucher has not been partially redeemed,
- target child is active in the caller's family,
- caller is an active parent, guardian or carer with management/spending rights or primary guardian status,
- caller owns the voucher, the voucher is already family-scoped, or caller has voucher management permission.

Assignments update `voucher_issuances`, insert `family_voucher_assignments`, notify the child account and write an audit log.

## Canteen Beneficiaries

The canteen order flow supports purchasing for `Me` or a linked child. The server validates non-self beneficiaries against active family relationships before writing `recipient_id` on the order.

## Current Limits

This phase does not implement real payment-provider top-ups, child spending controls at checkout, wallet debit settlement, family relationship removal safeguards, or full R2-backed attachment workflows.
