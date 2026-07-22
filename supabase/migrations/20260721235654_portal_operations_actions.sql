-- Operational write policies for the first usable club portal pass.
-- These complement the foundation policies without weakening public access.

drop policy if exists fixtures_manage_structure_or_team on public.fixtures;
create policy fixtures_manage_structure_or_team
on public.fixtures
for all
to authenticated
using (
  app_private.has_permission('club_structure.manage')
  or app_private.has_permission('teams.manage', team_id)
)
with check (
  app_private.has_permission('club_structure.manage')
  or app_private.has_permission('teams.manage', team_id)
);

drop policy if exists training_manage_structure_or_team on public.training_sessions;
create policy training_manage_structure_or_team
on public.training_sessions
for all
to authenticated
using (
  app_private.has_permission('club_structure.manage')
  or team_id is null
  or app_private.has_permission('teams.manage', team_id)
)
with check (
  app_private.has_permission('club_structure.manage')
  or team_id is null
  or app_private.has_permission('teams.manage', team_id)
);

drop policy if exists event_regs_manager_manage on public.event_registrations;
create policy event_regs_manager_manage
on public.event_registrations
for all
to authenticated
using (app_private.has_permission('events.manage'))
with check (app_private.has_permission('events.manage'));

drop policy if exists notifications_admin_manage on public.notifications;
create policy notifications_admin_manage
on public.notifications
for all
to authenticated
using (app_private.has_permission('communications.manage'))
with check (app_private.has_permission('communications.manage'));

drop policy if exists communication_admin_manage on public.communication_outbox;
create policy communication_admin_manage
on public.communication_outbox
for all
to authenticated
using (app_private.has_permission('communications.manage'))
with check (app_private.has_permission('communications.manage'));

drop policy if exists canteen_orders_create_own on public.canteen_orders;
create policy canteen_orders_create_own
on public.canteen_orders
for insert
to authenticated
with check (customer_id = auth.uid() or app_private.has_permission('canteen.orders.manage'));

drop policy if exists canteen_order_items_create_own on public.canteen_order_items;
create policy canteen_order_items_create_own
on public.canteen_order_items
for insert
to authenticated
with check (
  exists (
    select 1
    from public.canteen_orders o
    where o.id = order_id
      and (o.customer_id = auth.uid() or app_private.has_permission('canteen.orders.manage'))
  )
);

drop policy if exists merch_orders_create_own on public.merchandise_orders;
create policy merch_orders_create_own
on public.merchandise_orders
for insert
to authenticated
with check (customer_id = auth.uid() or app_private.has_permission('merchandise.manage'));
