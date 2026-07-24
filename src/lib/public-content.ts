import { createClient } from "@supabase/supabase-js";
import type { CollectionEntry } from "astro:content";
import type { Database, Json } from "../types/database.types";

export type PublicArticle = {
  id: string;
  title: string;
  slug: string;
  summary: string;
  body: string;
  category: string;
  image?: string | null;
  date: string;
  tags: string[];
};

export type PublicSponsor = {
  id: string;
  name: string;
  tier?: string | null;
  description?: string | null;
  website?: string | null;
  logo?: string | null;
  sortOrder: number;
};

export type PublicAnnouncement = {
  id: string;
  title: string;
  message: string;
  linkUrl?: string | null;
  priority: number;
};

const client = () => {
  const supabaseUrl = import.meta.env.PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = import.meta.env.PUBLIC_SUPABASE_ANON_KEY;
  if (!supabaseUrl || !supabaseAnonKey) return null;
  return createClient<Database>(supabaseUrl, supabaseAnonKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false
    }
  });
};

const bodyText = (body: Json) => {
  if (body && typeof body === "object" && !Array.isArray(body) && typeof body.text === "string") return body.text;
  return "";
};

export const markdownArticle = (article: CollectionEntry<"news">): PublicArticle => ({
  id: article.id,
  title: article.data.title,
  slug: article.data.slug ?? article.id,
  summary: article.data.summary,
  body: "",
  category: article.data.category,
  image: article.data.image,
  date: article.data.date.toISOString(),
  tags: article.data.tags ?? []
});

export const markdownSponsor = (sponsor: CollectionEntry<"sponsors">): PublicSponsor => ({
  id: sponsor.id,
  name: sponsor.data.name,
  tier: sponsor.data.tier,
  description: sponsor.data.description,
  website: sponsor.data.website,
  logo: sponsor.data.logo,
  sortOrder: sponsor.data.sortOrder
});

export const markdownAnnouncement = (announcement: CollectionEntry<"announcements">): PublicAnnouncement => ({
  id: announcement.id,
  title: announcement.data.title,
  message: announcement.data.message,
  linkUrl: announcement.data.linkUrl,
  priority: announcement.data.priority
});

export const fetchPublicArticles = async (limit = 20): Promise<PublicArticle[]> => {
  const supabase = client();
  if (!supabase) return [];

  const { data, error } = await supabase
    .from("content_articles")
    .select("id,title,slug,summary,body,category,featured_image_url,publish_at,updated_at,tags")
    .eq("workflow_status", "published")
    .or(`publish_at.is.null,publish_at.lte.${new Date().toISOString()}`)
    .order("publish_at", { ascending: false, nullsFirst: false })
    .order("updated_at", { ascending: false })
    .limit(limit);

  if (error) return [];

  return (data ?? []).map((article) => ({
    id: article.id,
    title: article.title,
    slug: article.slug,
    summary: article.summary ?? "",
    body: bodyText(article.body),
    category: article.category ?? "Club news",
    image: article.featured_image_url,
    date: article.publish_at ?? article.updated_at,
    tags: article.tags ?? []
  }));
};

export const fetchPublicArticleBySlug = async (slug: string): Promise<PublicArticle | null> => {
  const supabase = client();
  if (!supabase) return null;

  const { data, error } = await supabase
    .from("content_articles")
    .select("id,title,slug,summary,body,category,featured_image_url,publish_at,updated_at,tags")
    .eq("slug", slug)
    .eq("workflow_status", "published")
    .or(`publish_at.is.null,publish_at.lte.${new Date().toISOString()}`)
    .maybeSingle();

  if (error || !data) return null;

  return {
    id: data.id,
    title: data.title,
    slug: data.slug,
    summary: data.summary ?? "",
    body: bodyText(data.body),
    category: data.category ?? "Club news",
    image: data.featured_image_url,
    date: data.publish_at ?? data.updated_at,
    tags: data.tags ?? []
  };
};

export const fetchPublicSponsors = async (limit = 12): Promise<PublicSponsor[]> => {
  const supabase = client();
  if (!supabase) return [];

  const today = new Date().toISOString().slice(0, 10);
  const { data, error } = await supabase
    .from("sponsors")
    .select("id,name,tier,description,website_url,logo_url,display_priority,starts_on,ends_on")
    .eq("status", "active")
    .or(`starts_on.is.null,starts_on.lte.${today}`)
    .or(`ends_on.is.null,ends_on.gte.${today}`)
    .order("display_priority", { ascending: true })
    .order("name", { ascending: true })
    .limit(limit);

  if (error) return [];

  return (data ?? []).map((sponsor) => ({
    id: sponsor.id,
    name: sponsor.name,
    tier: sponsor.tier,
    description: sponsor.description,
    website: sponsor.website_url,
    logo: sponsor.logo_url,
    sortOrder: sponsor.display_priority
  }));
};

export const fetchPublicAnnouncement = async (): Promise<PublicAnnouncement | null> => {
  const supabase = client();
  if (!supabase) return null;

  const now = new Date().toISOString();
  const { data, error } = await supabase
    .from("club_announcements")
    .select("id,title,message,priority")
    .eq("status", "published")
    .in("audience", ["public", "members"])
    .or(`starts_at.is.null,starts_at.lte.${now}`)
    .or(`ends_at.is.null,ends_at.gt.${now}`)
    .order("priority", { ascending: true })
    .limit(1)
    .maybeSingle();

  if (error || !data) return null;

  return {
    id: data.id,
    title: data.title,
    message: data.message,
    linkUrl: "/news/",
    priority: data.priority
  };
};
