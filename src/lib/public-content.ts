import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { CollectionEntry } from "astro:content";
import type { Database, Json } from "../types/database.types";
import { getPublicMediaUrl, getSafeExternalImageUrl } from "./media";
import { PAGE_BOUNDS, clampLimit } from "./pagination";
import type { PublicEventSummary } from "./public-events";
import type { PublicSocialPost } from "./public-social";
import type { PublicTeamSummary } from "./public-teams";

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

export const markdownAnnouncement = (announcement: CollectionEntry<"announcements">): PublicAnnouncement => ({
  id: announcement.id,
  title: announcement.data.title,
  message: announcement.data.message,
  linkUrl: announcement.data.linkUrl,
  priority: announcement.data.priority
});

export const fetchPublicArticles = async (limit = 20, offset = 0): Promise<{ articles: PublicArticle[]; total: number }> => {
  const supabase = client();
  if (!supabase) return { articles: [], total: 0 };

  const { data, error, count } = await supabase
    .from("content_articles")
    .select("id,title,slug,summary,body,category,featured_image_url,publish_at,updated_at,tags", { count: "exact" })
    .eq("workflow_status", "active")
    .or(`publish_at.is.null,publish_at.lte.${new Date().toISOString()}`)
    .order("publish_at", { ascending: false, nullsFirst: false })
    .order("updated_at", { ascending: false })
    .range(offset, offset + limit - 1);

  if (error) return { articles: [], total: 0 };

  return {
    articles: (data ?? []).map((article) => ({
      id: article.id,
      title: article.title,
      slug: article.slug,
      summary: article.summary ?? "",
      body: bodyText(article.body),
      category: article.category ?? "Club news",
      image: getSafeExternalImageUrl(article.featured_image_url),
      date: article.publish_at ?? article.updated_at,
      tags: article.tags ?? []
    })),
    total: count ?? 0
  };
};

export const fetchPublicArticleBySlug = async (
  slug: string,
): Promise<PublicArticle | null> => {
  const supabase = client();
  if (!supabase) return null;

  const { data, error } = await supabase
    .from("content_articles")
    .select(
      "id,title,slug,summary,body,category,featured_image_url,publish_at,updated_at,tags",
    )
    .eq("slug", slug)
    .eq("workflow_status", "active")
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
    image: getSafeExternalImageUrl(data.featured_image_url),
    date: data.publish_at ?? data.updated_at,
    tags: data.tags ?? [],
  };
};

export const fetchPublicSponsors = async (supabase: any, context: any, limit = 12): Promise<PublicSponsor[]> => {
  const today = new Date().toISOString().slice(0, 10);
  const { data, error } = await supabase
    .from("sponsors")
    .select("id,name,tier,description,website_url,logo_object_key,logo_url,display_priority,starts_on,ends_on")
    .eq("status", "active")
    .or(`starts_on.is.null,starts_on.lte.${today}`)
    .or(`ends_on.is.null,ends_on.gte.${today}`)
    .order("display_priority", { ascending: true })
    .order("name", { ascending: true })
    .limit(limit);

  if (error) return [];

  return (data ?? []).map((sponsor: any) => ({
    id: sponsor.id,
    name: sponsor.name,
    tier: sponsor.tier,
    description: sponsor.description,
    website: sponsor.website_url,
    logo: getPublicMediaUrl(sponsor.logo_object_key, context) ?? getSafeExternalImageUrl(sponsor.logo_url),
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
    .eq("status", "active")
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

export type HomepageContent = {
  articles: PublicArticle[];
  socialPosts: PublicSocialPost[];
  spotlightTeam: PublicTeamSummary | null;
  activeTeamCount: number;
  sponsors: PublicSponsor[];
  events: PublicEventSummary[];
  announcement: PublicAnnouncement | null;
};

/**
 * Single round-trip homepage content via the `get_homepage_content` RPC.
 * Returns null on any failure so callers can fall back to per-section fetches or markdown.
 */
export const fetchHomepageContent = async (
  supabase: SupabaseClient<Database>,
  context: { locals?: unknown },
  options: { articleLimit?: number; socialLimit?: number; sponsorLimit?: number; eventLimit?: number } = {}
): Promise<HomepageContent | null> => {
  try {
    const { data, error } = await (supabase as any).rpc("get_homepage_content", {
      article_limit: clampLimit(options.articleLimit, PAGE_BOUNDS.homepage),
      social_limit: clampLimit(options.socialLimit, PAGE_BOUNDS.homepage),
      sponsor_limit: clampLimit(options.sponsorLimit, PAGE_BOUNDS.homepage),
      event_limit: clampLimit(options.eventLimit, PAGE_BOUNDS.homepage)
    });
    if (error || !data) return null;

    const articles: PublicArticle[] = ((data.articles ?? []) as any[]).map((article) => ({
      id: article.id,
      title: article.title,
      slug: article.slug,
      summary: article.summary ?? "",
      body: "",
      category: article.category ?? "Club news",
      image: getSafeExternalImageUrl(article.featured_image_url),
      date: article.publish_at ?? article.updated_at,
      tags: article.tags ?? []
    }));

    const socialPosts: PublicSocialPost[] = ((data.social_posts ?? []) as any[]).map((post) => ({
      id: post.id,
      platform: post.platform,
      title: post.title,
      caption: post.caption,
      postUrl: post.post_url,
      imageUrl: getPublicMediaUrl(post.image_object_key, context),
      imageAltText: post.image_alt_text,
      publishedAt: post.published_at,
      featured: post.featured
    }));

    const sponsors: PublicSponsor[] = ((data.sponsors ?? []) as any[]).map((sponsor) => ({
      id: sponsor.id,
      name: sponsor.name,
      tier: sponsor.tier,
      description: sponsor.description,
      website: sponsor.website_url,
      logo: getPublicMediaUrl(sponsor.logo_object_key, context) ?? getSafeExternalImageUrl(sponsor.logo_url),
      sortOrder: sponsor.display_priority
    }));

    const events: PublicEventSummary[] = ((data.events ?? []) as any[]).map((event) => {
      const types = ((event.ticket_types ?? []) as any[]).filter((type) => type.active);
      const prices = types.map((type) => type.price_cents);
      return {
        id: event.id,
        slug: event.slug,
        name: event.title,
        summary: event.description,
        imageUrl: getPublicMediaUrl(event.image_object_key, context) ?? getSafeExternalImageUrl(event.image_url),
        startsAt: event.starts_at,
        endsAt: event.ends_at,
        venueName: event.venue ?? null,
        venueSuburb: null,
        minimumPriceCents: prices.length ? Math.min(...prices) : null,
        currency: types[0]?.currency ?? "AUD",
        isFree: prices.length ? prices.every((price: number) => price === 0) : true,
        isSoldOut: false
      };
    });

    const spotlight = data.spotlight_team as any;
    const spotlightTeam: PublicTeamSummary | null = spotlight
      ? {
          id: spotlight.id,
          slug: spotlight.slug,
          name: spotlight.name,
          division: spotlight.division ?? null,
          competition: spotlight.competition_name ?? null,
          seasonName: spotlight.season_name ?? null,
          summary: spotlight.summary ?? null,
          imageUrl: getPublicMediaUrl(spotlight.image_object_key, context)
        }
      : null;

    const rpcAnnouncement = data.announcement as any;
    const announcement: PublicAnnouncement | null = rpcAnnouncement
      ? {
          id: rpcAnnouncement.id,
          title: rpcAnnouncement.title,
          message: rpcAnnouncement.message,
          linkUrl: "/news/",
          priority: rpcAnnouncement.priority
        }
      : null;

    return {
      articles,
      socialPosts,
      spotlightTeam,
      activeTeamCount: Number(data.active_team_count ?? 0),
      sponsors,
      events,
      announcement
    };
  } catch {
    return null;
  }
};
