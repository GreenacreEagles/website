import { defineCollection, z } from "astro:content";
import { glob } from "astro/loaders";

const imageField = z.string().optional();
const ctaField = z
  .object({
    text: z.string(),
    href: z.string()
  })
  .optional();

const news = defineCollection({
  loader: glob({ pattern: "**/*.md", base: "./src/content/news" }),
  schema: z.object({
    title: z.string(),
    slug: z.string().optional(),
    date: z.coerce.date(),
    author: z.string().default("Greenacre Eagles FC"),
    summary: z.string(),
    image: imageField,
    tags: z.array(z.string()).default([]),
    category: z.string().default("Club news"),
    featured: z.boolean().default(false)
  })
});

const weeklyHighlights = defineCollection({
  loader: glob({ pattern: "**/*.md", base: "./src/content/weekly-highlights" }),
  schema: z.object({
    title: z.string(),
    slug: z.string().optional(),
    weekOf: z.coerce.date(),
    summary: z.string(),
    image: imageField,
    cta: ctaField,
    highlightCards: z
      .array(
        z.object({
          title: z.string(),
          text: z.string(),
          metric: z.string().optional(),
          image: imageField,
          linkText: z.string().optional(),
          linkUrl: z.string().optional()
        })
      )
      .default([])
  })
});

const socialPosts = defineCollection({
  loader: glob({ pattern: "**/*.md", base: "./src/content/social-posts" }),
  schema: z.object({
    slug: z.string().optional(),
    platform: z.enum(["Instagram", "TikTok", "Facebook", "YouTube", "Other"]),
    title: z.string(),
    caption: z.string(),
    postUrl: z.string(),
    date: z.coerce.date(),
    thumbnail: imageField,
    featured: z.boolean().default(true),
    sortOrder: z.number().default(100),
    embed: z.boolean().default(false)
  })
});

const sponsors = defineCollection({
  loader: glob({ pattern: "**/*.md", base: "./src/content/sponsors" }),
  schema: z.object({
    slug: z.string().optional(),
    name: z.string(),
    logo: imageField,
    website: z.string().optional(),
    tier: z.enum(["Major Partner", "Gold", "Silver", "Community", "In-kind"]),
    description: z.string(),
    sortOrder: z.number().default(100)
  })
});

const fundraisers = defineCollection({
  loader: glob({ pattern: "**/*.md", base: "./src/content/fundraisers" }),
  schema: z.object({
    slug: z.string().optional(),
    title: z.string(),
    goalAmount: z.number(),
    currentAmount: z.number(),
    description: z.string(),
    image: imageField,
    ctaText: z.string(),
    ctaLink: z.string(),
    status: z.enum(["active", "completed", "paused"]).default("active")
  })
});

const events = defineCollection({
  loader: glob({ pattern: "**/*.md", base: "./src/content/events" }),
  schema: z.object({
    slug: z.string().optional(),
    title: z.string(),
    dateTime: z.coerce.date(),
    location: z.string(),
    summary: z.string(),
    ctaLink: z.string().optional(),
    eventType: z.string().default("Club event")
  })
});

const gallery = defineCollection({
  loader: glob({ pattern: "**/*.md", base: "./src/content/gallery" }),
  schema: z.object({
    slug: z.string().optional(),
    title: z.string(),
    image: z.string(),
    date: z.coerce.date(),
    category: z.string(),
    description: z.string()
  })
});

const teams = defineCollection({
  loader: glob({ pattern: "**/*.md", base: "./src/content/teams" }),
  schema: z.object({
    slug: z.string().optional(),
    name: z.string(),
    ageGroup: z.string(),
    coach: z.string().default("To be confirmed"),
    training: z.string(),
    image: imageField,
    description: z.string(),
    spotlight: z.boolean().default(false),
    sortOrder: z.number().default(100)
  })
});

const announcements = defineCollection({
  loader: glob({ pattern: "**/*.md", base: "./src/content/announcements" }),
  schema: z.object({
    slug: z.string().optional(),
    title: z.string(),
    message: z.string(),
    linkText: z.string().optional(),
    linkUrl: z.string().optional(),
    active: z.boolean().default(true),
    priority: z.number().default(100)
  })
});

export const collections = {
  news,
  "weekly-highlights": weeklyHighlights,
  "social-posts": socialPosts,
  sponsors,
  fundraisers,
  events,
  gallery,
  teams,
  announcements
};
