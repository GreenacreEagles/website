-- Public database-backed publishing support for news, announcements and sponsors.

create index if not exists content_articles_public_publish_idx
on public.content_articles (workflow_status, publish_at desc, updated_at desc);

create index if not exists content_articles_category_idx
on public.content_articles (category, publish_at desc)
where workflow_status = 'published';

create index if not exists content_articles_tags_gin_idx
on public.content_articles using gin (tags);

create index if not exists club_announcements_public_idx
on public.club_announcements (status, audience, priority, starts_at, ends_at);

create index if not exists sponsors_public_display_idx
on public.sponsors (status, display_priority, name);

create or replace function app_private.content_article_before_write()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  new.slug := coalesce(nullif(trim(new.slug), ''), app_private.slugify(new.title));

  if new.workflow_status = 'published' and new.publish_at is null then
    new.publish_at := now();
  end if;

  return new;
end;
$$;

drop trigger if exists content_article_before_write on public.content_articles;
create trigger content_article_before_write
before insert or update on public.content_articles
for each row execute function app_private.content_article_before_write();

grant select on public.content_articles to anon, authenticated;
grant insert, update, delete on public.content_articles to authenticated;

grant select on public.club_announcements to anon, authenticated;
grant insert, update, delete on public.club_announcements to authenticated;

grant select on public.sponsors to anon, authenticated;
grant insert, update, delete on public.sponsors to authenticated;
