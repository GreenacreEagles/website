# Role Management

Roles and permissions are controlled in Supabase through `roles`, `permissions`, `role_permissions` and `user_role_assignments`.

## Operating Model

Members cannot request roles or team access from the portal. Authorised administrators assign roles in `/admin/users/[id]/`.

Historical `role_requests` records remain in the database for audit continuity, but the latest migration removes role request routes and revokes request/review RPC execution from normal authenticated users.

## Effective Permissions

Effective permissions are the union of valid active role assignments. The database helper checks:

- assignment status is `active`,
- start time has passed,
- expiry time has not passed,
- team scope matches where supplied,
- season scope matches where supplied,
- role permissions include the requested permission or `*`.

The portal session loader asks Supabase for each known permission instead of trusting browser state or user-editable metadata.

## Protected Roles

System roles such as `general_user`, `club_administrator` and `super_administrator` are seeded and protected. Normal administrators cannot grant `super_administrator`; only a current super administrator can do that through the protected RPC.

## Team Access

Team access is derived from:

- active team-scoped role assignments,
- active team staff rows,
- player records on the team,
- active family guardian relationships to players,
- authorised team or club administrators.

The `public.member_team_ids()` RPC returns a member-safe list of accessible team ids and relationship labels for portal pages.

Active `coach`, `assistant_coach` and `team_manager` rows in `team_staff` also permit team operations such as publishing team posts and submitting match reports for that team through the protected RLS helper.
