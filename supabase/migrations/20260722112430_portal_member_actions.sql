-- Simple member portal actions for orders, notifications, events and volunteer shifts.

drop policy if exists merch_orders_create_own on public.merchandise_orders;
create policy merch_orders_create_own
on public.merchandise_orders
for insert
to authenticated
with check (customer_id = auth.uid() or app_private.has_permission('merchandise.manage'));

drop policy if exists notifications_own_update on public.notifications;
create policy notifications_own_update
on public.notifications
for update
to authenticated
using (recipient_id = auth.uid() or app_private.has_permission('communications.manage'))
with check (recipient_id = auth.uid() or app_private.has_permission('communications.manage'));

drop policy if exists event_regs_own_update on public.event_registrations;
create policy event_regs_own_update
on public.event_registrations
for update
to authenticated
using (registered_by = auth.uid() or attendee_id = auth.uid() or app_private.has_permission('events.manage'))
with check (registered_by = auth.uid() or attendee_id = auth.uid() or app_private.has_permission('events.manage'));

drop policy if exists events_members_published on public.club_events;
create policy events_members_published
on public.club_events
for select
to authenticated
using (status = 'published' and visibility in ('public', 'members'));
