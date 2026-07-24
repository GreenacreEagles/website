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

Notifications use the existing `notifications` table. The dashboard supports unread display and mark-all-read through `/api/portal/notification/`. Notifications may now carry `action_url`; otherwise the dashboard falls back to `related_entity_type` and `related_entity_id` routing.

Members manage category preferences from `/portal/account/`. Preferences are stored in `notification_preferences` for portal, email and SMS channels across club notices, team posts, commerce, events, volunteers and resources. The broad profile-level email/SMS switches still act as channel defaults.

Outbound email and SMS jobs are queued in `communication_outbox`. The worker endpoint `/api/workers/communication-outbox/` lets a trusted scheduled worker claim, complete or fail jobs using `COMMUNICATION_WORKER_SECRET`. The source does not send production email/SMS directly; a real delivery provider must call the worker contract and then mark each job complete or failed.

## Volunteers

`/portal/volunteers/` shows open or filled volunteer shifts, remaining capacity and the signed-in member's assignments. Members can sign up, check in, cancel or request a replacement through RPC-backed actions so shift capacity and status remain consistent under concurrent submissions.

## Coaching Resources

`/portal/coaching/` is permission-controlled for coaches, team staff and club administrators. It lists published coaching resources with search, resource-type filtering, age-group filtering, tags, duration, equipment and external links.

## Public Content

The homepage, `/news/`, `/news/[slug]/` and `/sponsors/` now read published Supabase content first for articles, announcements and sponsor records. Existing Markdown collections remain as fallback content when no matching database rows are published.

## Current Limits

The commerce, club-operations and publishing phases add canteen catalogue management, stock-aware canteen ordering, staff order transitions, payment marking, pickup codes, automatic wallet voucher issuance for paid voucher products, voucher QR scanning and reversal, wallet account creation, manual top-up settlement, provider webhook settlement, controlled wallet adjustments, ledger reversal, merchandise catalogue management, stock-backed merchandise checkout, merchandise order operations, volunteer shift rostering, the coaching resource library, database-backed public articles, announcements and sponsors, notification preferences and a provider-neutral communication outbox. Full production completion still requires applying the latest migration, regenerating database types, configuring live payment provider credentials, connecting a real email/SMS delivery worker, R2 upload endpoints, event ticket QR scanning, public store checkout and broader automated coverage.
