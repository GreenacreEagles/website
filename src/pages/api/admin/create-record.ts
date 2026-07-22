import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { optionalUuidSchema, redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const nullableText = (max = 500) => z.preprocess((value) => (value === "" ? null : value), z.string().trim().max(max).nullable().optional());
const nullableDate = z.preprocess((value) => (value === "" ? null : value), z.string().nullable().optional());
const boolFromCheckbox = z.preprocess((value) => value === "on" || value === "true", z.boolean());
const centsFromDollars = z.preprocess((value) => Math.round(Number(value || 0) * 100), z.number().int().min(0));
const optionalNumber = z.preprocess((value) => (value === "" ? null : Number(value)), z.number().int().nullable().optional());

const slugify = (value: string) =>
  value
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);

const splitList = (value?: string | null) =>
  (value ?? "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);

const hashToken = async (token: string) => {
  const bytes = new TextEncoder().encode(token);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
};

const token = () => crypto.randomUUID().replaceAll("-", "").slice(0, 12).toUpperCase();

const schemas = {
  venue: z.object({
    name: z.string().trim().min(2).max(120),
    address: nullableText(240),
    suburb: nullableText(80),
    postcode: nullableText(12),
    notes: nullableText(500)
  }),
  competition: z.object({
    name: z.string().trim().min(2).max(140),
    season_id: optionalUuidSchema,
    external_url: nullableText(300)
  }),
  fixture: z.object({
    season_id: uuidSchema,
    team_id: uuidSchema,
    competition_id: optionalUuidSchema,
    venue_id: optionalUuidSchema,
    opponent: z.string().trim().min(2).max(140),
    round: nullableText(80),
    starts_at: z.string().min(1),
    home_away: z.enum(["home", "away", "neutral"]),
    status: z.enum(["scheduled", "postponed", "cancelled", "completed"]),
    external_url: nullableText(300)
  }),
  training: z.object({
    team_id: optionalUuidSchema,
    venue_id: optionalUuidSchema,
    starts_at: z.string().min(1),
    ends_at: nullableDate,
    notes: nullableText(500),
    status: z.enum(["scheduled", "cancelled", "completed"])
  }),
  volunteerOpportunity: z.object({
    title: z.string().trim().min(2).max(140),
    description: nullableText(600),
    opportunity_type: z.string().trim().min(2).max(80),
    required_permission: nullableText(120),
    status: z.enum(["active", "paused", "archived"])
  }),
  volunteerShift: z.object({
    opportunity_id: uuidSchema,
    venue_id: optionalUuidSchema,
    starts_at: z.string().min(1),
    ends_at: nullableDate,
    capacity: z.coerce.number().int().min(1).max(200),
    status: z.enum(["open", "filled", "cancelled", "completed"])
  }),
  canteenVenue: z.object({
    name: z.string().trim().min(2).max(120),
    venue_id: optionalUuidSchema,
    is_active: boolFromCheckbox
  }),
  canteenCategory: z.object({
    name: z.string().trim().min(2).max(80),
    display_order: z.coerce.number().int().min(0).default(0),
    is_active: boolFromCheckbox
  }),
  canteenProduct: z.object({
    category_id: optionalUuidSchema,
    name: z.string().trim().min(2).max(120),
    description: nullableText(500),
    price: centsFromDollars,
    preparation_minutes: z.coerce.number().int().min(0).max(120).default(5),
    max_quantity_per_order: optionalNumber,
    dietary_info: nullableText(200),
    allergen_info: nullableText(200),
    is_active: boolFromCheckbox,
    is_sold_out: boolFromCheckbox
  }),
  voucher: z.object({
    beneficiary_id: optionalUuidSchema,
    family_id: optionalUuidSchema,
    team_id: optionalUuidSchema,
    venue_id: optionalUuidSchema,
    issue_reason: nullableText(300),
    voucher_type: z.enum(["fixed_amount", "specific_product", "category", "meal_deal", "declining_balance"]),
    value: centsFromDollars,
    expires_at: nullableDate
  }),
  event: z.object({
    title: z.string().trim().min(2).max(160),
    slug: nullableText(120),
    description: nullableText(800),
    venue_id: optionalUuidSchema,
    starts_at: z.string().min(1),
    ends_at: nullableDate,
    capacity: optionalNumber,
    price: centsFromDollars,
    visibility: z.enum(["public", "members", "private"]),
    status: z.enum(["draft", "published", "cancelled", "completed", "archived"])
  }),
  announcement: z.object({
    title: z.string().trim().min(2).max(160),
    message: z.string().trim().min(2).max(1200),
    audience: z.string().trim().min(2).max(80),
    priority: z.coerce.number().int().min(0).max(100),
    starts_at: nullableDate,
    ends_at: nullableDate,
    status: z.enum(["draft", "published", "archived"])
  }),
  sponsor: z.object({
    name: z.string().trim().min(2).max(160),
    tier: nullableText(80),
    description: nullableText(600),
    website_url: nullableText(300),
    logo_url: nullableText(300),
    starts_on: nullableDate,
    ends_on: nullableDate,
    display_locations: nullableText(200),
    display_priority: z.coerce.number().int().min(0).max(999),
    contact_name: nullableText(120),
    contact_email: nullableText(160),
    internal_notes: nullableText(800),
    status: z.enum(["active", "inactive", "archived"])
  }),
  article: z.object({
    title: z.string().trim().min(2).max(180),
    slug: nullableText(140),
    summary: nullableText(500),
    category: nullableText(80),
    body: z.string().trim().min(2).max(6000),
    featured_image_url: nullableText(300),
    tags: nullableText(240),
    publish_at: nullableDate,
    workflow_status: z.enum(["draft", "in_review", "scheduled", "published", "archived"])
  }),
  notification: z.object({
    recipient_id: uuidSchema,
    title: z.string().trim().min(2).max(160),
    body: z.string().trim().min(2).max(1200),
    channel: z.enum(["in_app", "email", "sms"]).default("in_app")
  })
};

const actionConfig = {
  venue: { permissions: ["club_structure.manage"], redirect: "/admin/teams/", success: "Venue created." },
  competition: { permissions: ["club_structure.manage"], redirect: "/admin/teams/", success: "Competition created." },
  fixture: { permissions: ["club_structure.manage", "teams.manage"], redirect: "/admin/fixtures/", success: "Fixture created." },
  training: { permissions: ["club_structure.manage", "teams.manage"], redirect: "/admin/fixtures/", success: "Training session created." },
  volunteerOpportunity: { permissions: ["volunteers.manage"], redirect: "/admin/volunteers/", success: "Volunteer opportunity created." },
  volunteerShift: { permissions: ["volunteers.manage"], redirect: "/admin/volunteers/", success: "Volunteer shift created." },
  canteenVenue: { permissions: ["canteen.manage"], redirect: "/admin/canteen/", success: "Canteen venue created." },
  canteenCategory: { permissions: ["canteen.manage"], redirect: "/admin/canteen/", success: "Canteen category created." },
  canteenProduct: { permissions: ["canteen.manage"], redirect: "/admin/canteen/", success: "Canteen product created." },
  voucher: { permissions: ["canteen.vouchers.manage"], redirect: "/admin/canteen/", success: "Voucher issued." },
  event: { permissions: ["events.manage"], redirect: "/admin/events/", success: "Event created." },
  announcement: { permissions: ["content.manage"], redirect: "/admin/content/", success: "Announcement created." },
  sponsor: { permissions: ["sponsors.manage"], redirect: "/admin/sponsors/", success: "Sponsor saved." },
  article: { permissions: ["content.manage"], redirect: "/admin/content/", success: "Article saved." },
  notification: { permissions: ["communications.manage"], redirect: "/admin/communications/", success: "Notification queued." }
} as const;

type Action = keyof typeof actionConfig;

export const POST: APIRoute = async (context) => {
  const form = Object.fromEntries(await context.request.formData());
  const action = form.action as Action;
  const config = actionConfig[action];
  if (!config) return context.redirect(redirectWithMessage("/admin/", "error", "Unknown admin action."));

  const session = await requirePermission(context, [...config.permissions]);
  if (!session) return context.redirect("/admin/");

  const parsed = schemas[action].safeParse(form);
  if (!parsed.success) {
    return context.redirect(redirectWithMessage(config.redirect, "error", parsed.error.issues[0]?.message ?? "Check the form details."));
  }

  const data = parsed.data as any;
  let error: { message: string } | null = null;
  let success: string = config.success;

  if (action === "venue") {
    ({ error } = await session.supabase.from("venues").insert(data));
  } else if (action === "competition") {
    ({ error } = await session.supabase.from("competitions").insert(data));
  } else if (action === "fixture") {
    ({ error } = await session.supabase.from("fixtures").insert(data));
  } else if (action === "training") {
    ({ error } = await session.supabase.from("training_sessions").insert(data));
  } else if (action === "volunteerOpportunity") {
    ({ error } = await session.supabase.from("volunteer_opportunities").insert(data));
  } else if (action === "volunteerShift") {
    ({ error } = await session.supabase.from("volunteer_shifts").insert(data));
  } else if (action === "canteenVenue") {
    ({ error } = await session.supabase.from("canteen_venues").insert(data));
  } else if (action === "canteenCategory") {
    ({ error } = await session.supabase.from("canteen_categories").insert(data));
  } else if (action === "canteenProduct") {
    ({ error } = await session.supabase.from("canteen_products").insert({
      category_id: data.category_id ?? null,
      name: data.name,
      description: data.description ?? null,
      price_cents: data.price,
      dietary_info: splitList(data.dietary_info),
      allergen_info: splitList(data.allergen_info),
      preparation_minutes: data.preparation_minutes,
      max_quantity_per_order: data.max_quantity_per_order,
      is_active: data.is_active,
      is_sold_out: data.is_sold_out
    }));
  } else if (action === "voucher") {
    const rawToken = token();
    ({ error } = await session.supabase.from("voucher_issuances").insert({
      token_hash: await hashToken(rawToken),
      beneficiary_id: data.beneficiary_id ?? null,
      family_id: data.family_id ?? null,
      team_id: data.team_id ?? null,
      venue_id: data.venue_id ?? null,
      issued_by: session.user.id,
      issue_reason: data.issue_reason ?? null,
      voucher_type: data.voucher_type,
      original_value_cents: data.value,
      remaining_value_cents: data.value,
      expires_at: data.expires_at ?? null,
      status: "active"
    }));
    if (!error && data.beneficiary_id) {
      await session.supabase.from("notifications").insert({
        recipient_id: data.beneficiary_id,
        title: "Canteen voucher issued",
        body: `Your Greenacre Eagles canteen voucher code is ${rawToken}.`
      });
    }
    success = `Voucher issued. Code: ${rawToken}`;
  } else if (action === "event") {
    ({ error } = await session.supabase.from("club_events").insert({
      ...data,
      slug: data.slug || slugify(data.title),
      price_cents: data.price
    }));
  } else if (action === "announcement") {
    ({ error } = await session.supabase.from("club_announcements").insert({ ...data, created_by: session.user.id }));
  } else if (action === "sponsor") {
    ({ error } = await session.supabase.from("sponsors").insert({ ...data, display_locations: splitList(data.display_locations) }));
  } else if (action === "article") {
    ({ error } = await session.supabase.from("content_articles").insert({
      title: data.title,
      slug: data.slug || slugify(data.title),
      summary: data.summary ?? null,
      category: data.category ?? null,
      body: { type: "plain_text", text: data.body },
      featured_image_url: data.featured_image_url ?? null,
      tags: splitList(data.tags),
      publish_at: data.publish_at ?? null,
      workflow_status: data.workflow_status,
      author_id: session.user.id
    }));
  } else if (action === "notification") {
    const payload = { title: data.title, body: data.body };
    ({ error } = await session.supabase.from("notifications").insert({ recipient_id: data.recipient_id, title: data.title, body: data.body }));
    if (!error && data.channel !== "in_app") {
      await session.supabase.from("communication_outbox").insert({
        recipient_id: data.recipient_id,
        channel: data.channel,
        template_key: "admin_message",
        payload
      });
    }
  }

  return context.redirect(redirectWithMessage(config.redirect, error ? "error" : "success", error?.message ?? success));
};
