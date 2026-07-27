# Role and access management

The portal uses three independent access dimensions: global roles, team-scoped positions, and volunteer/WWCC compliance. Do not model a team position or compliance state as a global role.

## Global roles

| Role | Purpose | Core access |
|---|---|---|
| General User | Standard member portal access | Own account, notifications, linked teams, registrations, orders and member stores |
| Club Admin | Full club administration | Every active standard application permission |
| Registrar | Registrations, players, volunteers and team assignments | Users needed for registration work, families, registrations, team membership, volunteer and WWCC administration |
| Content Editor | News, socials, resources and sponsors | Content, social profiles/posts, sponsors and coaching resources |
| Event Manager | Club events and registrations | Event CRUD, registrations, attendance, scanning and event reporting |
| Merchandise Manager | Merchandise products and orders | Merchandise catalogue, orders and fulfilment |
| Canteen Manager | Canteen products, orders and reporting | Full canteen operations, reports, refunds/reversals and fulfilment |
| Canteen Staff | Canteen preparation and QR collection | Active order view, prepare/ready/collect, voucher scan/redeem only |

Super Administrator is retained only as a technical bootstrap/emergency role. It is hidden from the normal role catalog and receives the wildcard permission. General User is automatically provisioned and cannot be removed. Users may hold multiple global roles.

## Team positions

Player, Coach and Team Manager use the existing player_records/team_players and team_staff architecture. They are assigned to a specific team whose season supplies the season scope. Assignments record state, dates, actor and timestamps. Coach and Team Manager activation requires approved volunteer status plus verified or exempt WWCC. The team permission helpers always check the target team, so one team never implies another.

- Player: assigned-team read and interaction only.
- Coach: assigned-team posts, match/training and appropriate member information.
- Team Manager: assigned-team communication and match-day administration.

## Compliance

member_compliance records volunteer status (pending, approved, suspended, expired, rejected) and WWCC status (not_supplied, pending_verification, verified, expired, exempt, rejected), decision actors/dates/reasons, expiry and verification data. Approval grants no permission by itself. Full WWCC details are limited by RLS to the member, Club Admin and Registrar permission paths; general views show only status and expiry. Audit records mask the check number to its last four characters.

Suspending Canteen Staff removes the role's effective permissions in both permission helpers and portal context. Coach and Team Manager operations require current compliance, including a non-expired WWCC date when applicable.

## Permission matrix

| Capability | Club Admin | Registrar | Content | Event | Merchandise | Canteen Manager | Canteen Staff |
|---|---:|---:|---:|---:|---:|---:|---:|
| Users required for duties | Full | View | No | Event-only data | No | No | Fulfilment-only customer data |
| Roles/permissions | Full | No | No | No | No | No | No |
| Registrations/players/families | Full | Full | No | No | No | No | No |
| Team memberships | Full | Full | No | No | No | No | No |
| Volunteer/WWCC | Full | Full | No | No | No | No | No |
| Content/social/resources/sponsors | Full | No | Full | No | No | No | No |
| Events | Full | No | No | Full | No | No | No |
| Merchandise | Full | No | No | No | Full | No | No |
| Canteen products/pricing/reports | Full | No | No | No | No | Full | No |
| Canteen fulfilment/QR | Full | No | No | No | No | Full | Fulfil only |
| Audit/settings | Full | No | No | No | No | No | No |

Club Admin is mapped to every active standard permission rather than requiring all other roles. Permission keys are specific; obsolete roles.review and team_access.review are inactive.

## Assignment rules

Only authorised administrators call assign_user_role or revoke_user_role. Global role RPCs reject team/season scope, self-escalation, duplicate active assignments and removal of General User. Role and team requests are revoked at the database level and their UI/API routes are removed. save_team_assignment is the only admin workflow for supported team positions and writes an audit record. update_member_compliance validates decisions and writes a masked audit record.

## Migration mapping

| Previous model | Result |
|---|---|
| club_administrator | Renamed to club_admin |
| canteen_worker | Merged into canteen_staff; assignments preserved |
| volunteer_coordinator | Mapped to Registrar |
| scoped player | Migrated to player_records/team_players |
| scoped coach / assistant_coach | Migrated to Coach team_staff |
| scoped team_manager | Migrated to Team Manager team_staff |
| global player/coach/team_manager | Deactivated and retained as history |
| club_member, parent_guardian, treasurer and other obsolete global roles | Deactivated; active assignments revoked with history retained |
| super_administrator | Technical role retained and hidden |

## Route access

The admin navigation and route guards use the same permission keys. Content, Event, Merchandise and Canteen managers see only their modules. Registrar sees users needed for duties, teams, volunteers and WWCC. Canteen Staff stays in the normal portal at /portal/canteen-staff/ and cannot enter unrelated admin modules. My Roles is read-only and exposes no internal permission keys.

## Adding a permission

1. Add the smallest action-oriented permission key in a migration.
2. Map it only to roles that require it; Club Admin receives every active standard permission automatically during consolidation, but later migrations must also map new permissions intentionally.
3. Protect the route/API and the database mutation or RLS policy.
4. Add it to the typed permission source and route matrix.
5. Add negative tests for adjacent roles. Do not create a new role solely to represent a status, team position or one-off action.

## Validation and deployment

Run npm run typecheck, npm run lint, npm run build and npm run test:db. Apply migrations in filename order, regenerate src/types/database.types.ts, then execute supabase/tests/role_consolidation_smoke.sql. Verify a representative account for every role and confirm denied direct table/RPC operations as well as hidden navigation.
