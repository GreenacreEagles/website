import type { APIRoute } from "astro";
import { z } from "zod";
import { optionalUuidSchema, redirectWithMessage, uuidSchema } from "@lib/forms";
import { requirePermission } from "@lib/auth/guards";

export const prerender = false;

const schema = z.object({
  season_id: uuidSchema,
  competition_id: optionalUuidSchema,
  name: z.string().trim().min(2).max(100),
  slug: z.string().trim().regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/).max(120),
  summary: z.string().trim().max(500).optional(),
  sort_order: z.coerce.number().int().min(0).max(10000).default(100),
  public: z.preprocess((value) => value === "on" || value === "true", z.boolean()),
  division: z.string().trim().max(80).optional(),
  colour: z.string().trim().max(80).optional(),
  external_fixture_url: z.string().trim().max(300).optional(),
  status: z.enum(["active", "inactive"])
});

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["club_structure.manage"]);
  if (!session) return context.redirect("/admin/");
  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/admin/teams/", "error", parsed.error.issues[0]?.message ?? "Check the team details."));
  const { error } = await (session.supabase as any).from("teams").insert({
    season_id: parsed.data.season_id,
    competition_id: parsed.data.competition_id ?? null,
    name: parsed.data.name,
    slug: parsed.data.slug,
    summary: parsed.data.summary || null,
    sort_order: parsed.data.sort_order,
    public: parsed.data.public,
    division: parsed.data.division || null,
    colour: parsed.data.colour || null,
    external_fixture_url: parsed.data.external_fixture_url || null,
    status: parsed.data.status
  });
  return context.redirect(redirectWithMessage("/admin/teams/", error ? "error" : "success", error?.message ?? "Team created."));
};
