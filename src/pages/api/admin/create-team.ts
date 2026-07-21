import type { APIRoute } from "astro";
import { z } from "zod";
import { optionalUuidSchema, redirectWithMessage, uuidSchema } from "@lib/forms";
import { requirePermission } from "@lib/auth/guards";

export const prerender = false;

const schema = z.object({
  season_id: uuidSchema,
  age_group_id: optionalUuidSchema,
  name: z.string().trim().min(2).max(100),
  division: z.string().trim().max(80).optional(),
  status: z.enum(["draft", "active", "archived"])
});

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["club_structure.manage"]);
  if (!session) return context.redirect("/admin/");
  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/admin/teams/", "error", parsed.error.issues[0]?.message ?? "Check the team details."));
  const { error } = await session.supabase.from("teams").insert({
    season_id: parsed.data.season_id,
    age_group_id: parsed.data.age_group_id ?? null,
    name: parsed.data.name,
    division: parsed.data.division || null,
    status: parsed.data.status
  });
  return context.redirect(redirectWithMessage("/admin/teams/", error ? "error" : "success", error?.message ?? "Team created."));
};
