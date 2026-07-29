-- Correct the output-column aliases used by the admin reorder RPC.

create or replace function public.reorder_admin_items(target_kind text,target_ids uuid[])
returns integer language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); required_permission text; changed integer:=0; supplied integer; distinct_count integer;
begin
 if actor is null then raise exception 'Authentication required'; end if;
 supplied:=coalesce(array_length(target_ids,1),0);
 select count(distinct item_id) into distinct_count from unnest(coalesce(target_ids,'{}'::uuid[])) as listed(item_id);
 if supplied=0 or supplied<>distinct_count or supplied>500 then raise exception 'Invalid reorder list'; end if;
 case target_kind
  when 'canteen_categories' then required_permission:='canteen.manage';
  when 'social_posts' then required_permission:='social_posts.manage';
  when 'coaching_resources' then required_permission:='coaching_resources.manage';
  else raise exception 'Unsupported reorder target';
 end case;
 if not app_private.has_permission(required_permission) then raise exception 'Not authorised'; end if;
 if target_kind='canteen_categories' then
  with desired as (select item_id id,item_position::int*10 position from unnest(target_ids) with ordinality as listed(item_id,item_position)), updated as (
   update public.canteen_categories t set display_order=d.position,updated_at=now() from desired d where t.id=d.id and t.display_order<>d.position returning 1)
  select count(*) into changed from updated;
 elsif target_kind='social_posts' then
  with desired as (select item_id id,item_position::int*10 position from unnest(target_ids) with ordinality as listed(item_id,item_position)), updated as (
   update public.social_posts t set sort_order=d.position,updated_at=now(),updated_by=actor from desired d where t.id=d.id and t.sort_order<>d.position returning 1)
  select count(*) into changed from updated;
 else
  with desired as (select item_id id,item_position::int*10 position from unnest(target_ids) with ordinality as listed(item_id,item_position)), updated as (
   update public.coaching_resources t set sort_order=d.position,updated_at=now() from desired d where t.id=d.id and t.sort_order<>d.position returning 1)
  select count(*) into changed from updated;
 end if;
 perform app_private.write_audit_log(target_kind||'.reordered',target_kind,null,null,jsonb_build_object('ids',target_ids,'changed',changed),'Admin reorder');
 return changed;
end $$;
revoke all on function public.reorder_admin_items(text,uuid[]) from public,anon;
grant execute on function public.reorder_admin_items(text,uuid[]) to authenticated,service_role;
