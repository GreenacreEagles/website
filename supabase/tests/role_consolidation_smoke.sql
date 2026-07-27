begin;

do $$
declare role_count int; missing_general int; duplicate_general int; obsolete_active int; worker_refs int; staff_extra int;
begin
 select count(*) into role_count from public.roles where is_active and role_kind='global';
 if role_count<>8 then raise exception 'Expected 8 active global roles, found %',role_count; end if;
 select count(*) into obsolete_active from public.roles where is_active and key in('player','coach','assistant_coach','team_manager','canteen_worker','volunteer_coordinator');
 if obsolete_active<>0 then raise exception 'Obsolete roles remain active'; end if;
 select count(*) into worker_refs from public.user_role_assignments ura join public.roles r on r.id=ura.role_id where r.key='canteen_worker' and ura.status='active' and ura.revoked_at is null;
 if worker_refs<>0 then raise exception 'Active Canteen Worker assignments remain'; end if;
 select count(*) into missing_general from public.profiles p where not exists(select 1 from public.user_role_assignments ura join public.roles r on r.id=ura.role_id where ura.user_id=p.id and r.key='general_user' and ura.status='active' and ura.revoked_at is null and ura.team_id is null and ura.season_id is null);
 if missing_general<>0 then raise exception 'Existing users are missing General User'; end if;
 select count(*) into duplicate_general from(select ura.user_id from public.user_role_assignments ura join public.roles r on r.id=ura.role_id where r.key='general_user' and ura.status='active' and ura.revoked_at is null group by ura.user_id having count(*)>1)x;
 if duplicate_general<>0 then raise exception 'Duplicate active General User assignments remain'; end if;
 select count(*) into staff_extra from public.role_permissions rp join public.roles r on r.id=rp.role_id join public.permissions p on p.id=rp.permission_id where r.key='canteen_staff' and p.key not in('canteen.orders.view','canteen.orders.fulfil','canteen.vouchers.redeem','shop.canteen.scan','shop.canteen.redeem');
 if staff_extra<>0 then raise exception 'Canteen Staff has permissions beyond fulfilment'; end if;
 if not exists(select 1 from public.roles r join public.role_permissions rp on rp.role_id=r.id join public.permissions p on p.id=rp.permission_id where r.key='club_admin' and p.key='audit.read') then raise exception 'Club Admin is missing a standard permission'; end if;
 if exists(select 1 from public.roles r join public.role_permissions rp on rp.role_id=r.id join public.permissions p on p.id=rp.permission_id where r.key='registrar' and p.key in('content.manage','events.manage','merchandise.manage','canteen.manage','roles.manage','audit.read')) then raise exception 'Registrar has unrelated access'; end if;
 if has_function_privilege('authenticated','public.request_team_access(uuid,text,text)','execute') or has_function_privilege('authenticated','public.request_role(uuid,uuid,uuid,text,text,text)','execute') then raise exception 'Self-service access request RPC remains executable'; end if;
 if not has_function_privilege('authenticated','public.assign_user_role(uuid,uuid,uuid,uuid,timestamptz,timestamptz,text)','execute') then raise exception 'Role assignment RPC unavailable'; end if;
end;
$$;

rollback;
