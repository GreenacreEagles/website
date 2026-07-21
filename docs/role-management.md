# Role Management

Roles, permissions, role requests, and role assignments are controlled in Supabase.

## Public Roles

Authenticated users may request requestable roles such as coach, manager, volunteer coordinator, canteen roles, and player/guardian roles where configured.

Users cannot request or grant `super_administrator` from the public portal.

## Requests

Portal users submit role requests from `/portal/role-requests/`.

Supported request states include:

- `submitted`
- `under_review`
- `approved`
- `rejected`
- `withdrawn`
- `cancelled`

Users may withdraw their own pending requests.

## Assignments

Admins with the right permissions assign and revoke roles from the admin portal. Role assignments may be scoped to a team, season, or both depending on the role.

Super administrator assignment remains deliberately separate. The first super administrator must be created by the trusted SQL bootstrap function, and future super-administrator grants require an existing active super administrator.

## Database Enforcement

Role workflows use RLS-aware public RPCs granted to authenticated users only. Server routes call those RPCs after validating the signed-in user.
