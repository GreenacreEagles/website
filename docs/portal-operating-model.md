# Portal Operating Model

## Member Portal

The member portal navigation contains Dashboard, My Account, My Roles, Teams, Family, Events, Volunteers, Canteen, permission-controlled Canteen Staff, Wallet and Coaching Resources.

Removed from normal portal navigation: Role Requests, Fixtures and a separate Notifications page. Notifications are shown on the dashboard with action links back to the relevant area.

## Dashboard

`/portal/` is a tile-based mobile-first dashboard. It shows:

- large section tiles,
- unread notification count,
- wallet balance summary,
- active role count,
- actionable canteen, voucher, event and volunteer items,
- recent team posts,
- club notices.

## Teams

`/portal/teams/` uses `public.member_team_ids()` plus RLS to show only assigned or relationship-authorised teams, except for users with club/team administration permissions.

Team pages under `/portal/teams/[id]/` provide private team boards. Members can read posts, react once per post and answer polls once per respondent. Coaches, team managers and administrators with scoped permissions can publish posts and polls.

Fixtures remain in the schema for internal data continuity, but match and activity communication for members is now via team posts and pinned announcements.

Team pages also show active squad and staff lists where team RLS permits access. Assigned coaches, assistant coaches and team managers can submit draft or submitted match reports from the team page. Administrators with report review permission can review, close or request changes from `/admin/teams/`.

## Notifications

Notifications use the existing `notifications` table. The dashboard supports unread display and mark-all-read through `/api/portal/notification/`. New notification categories should set `related_entity_type` and `related_entity_id` so dashboard action links can route members to the right workflow.

## Current Limits

The first three source phases add foundations for team boards, portal navigation cleanup, family/guardian invitations, admin family linking, child canteen beneficiaries, family voucher assignment, squad/staff administration and match-report submission/review. Full production completion still requires applying the latest migration, regenerating database types, payment-provider integration, wallet debit/top-up settlement, R2 upload endpoints, event ticket QR scanning, public store checkout and broader automated coverage.
