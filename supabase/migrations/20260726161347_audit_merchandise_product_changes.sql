-- Keep merchandise product audit writes in the same database request and
-- transaction as the product mutation.

create or replace function app_private.audit_merchandise_product_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
begin
  perform app_private.write_audit_log(
    case tg_op
      when 'INSERT' then 'merchandise.product_created'
      when 'UPDATE' then 'merchandise.product_updated'
      else 'merchandise.product_deleted'
    end,
    'merchandise_product',
    coalesce(new.id, old.id),
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end,
    null
  );
  return coalesce(new, old);
end;
$$;

revoke all on function app_private.audit_merchandise_product_change() from public, anon, authenticated;

drop trigger if exists merchandise_products_audit_change on public.merchandise_products;
create trigger merchandise_products_audit_change
after insert or update or delete on public.merchandise_products
for each row execute function app_private.audit_merchandise_product_change();
