# Admin Portal

The admin portal is available under `/admin/` and is protected by server-side permission checks.

## Current Admin Areas

- `/admin/`: dashboard summary for users, teams, role requests, and assignments.
- `/admin/users/`: user search and status overview.
- `/admin/users/[id]/`: user profile, role requests, assignments, and direct role actions.
- `/admin/role-assignments/`: assign and revoke roles.
- `/admin/role-requests/`: review, approve, reject, or mark role requests under review.
- `/admin/roles/`: role catalog and permission visibility.
- `/admin/teams/`: seasons and teams foundation.
- `/admin/audit/`: audit event viewer.

## Access Model

Admin navigation is permission-aware. Users see only the areas they have permission to manage.

The current phase focuses on account, role, and team foundations. Canteen operations, volunteer rosters, player management, fixtures, content publishing, payments, and communications remain future build phases.

## Operational Notes

No one can access the admin portal until the first super administrator is bootstrapped in Supabase.

All privileged actions should continue to be implemented through server routes plus Supabase RLS/RPC checks, not client-side permission decisions.
