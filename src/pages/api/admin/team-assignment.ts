import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;
const schema = z.object({
  user_id: uuidSchema,
  team_id: uuidSchema,
  position: z.enum(["player", "coach", "team_manager"]),
  status: z.enum(["active", "inactive", "left"]).default("active"),
  starts_on: z.string().optional(),
  ends_on: z.string().optional(),
  return_to: z.string().optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["team_memberships.manage", "club_structure.manage"]);
  if (!session) return context.redirect("/admin/");
  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  const fallback = parsed.success && parsed.data.return_to ? parsed.data.return_to : "/admin/users/";
  if (!parsed.success) return context.redirect(redirectWithMessage(fallback, "error", parsed.error.issues[0]?.message ?? "Check the team assignment."));
  const { error } = await session.supabase.rpc("save_team_assignment", {
    target_user_id: parsed.data.user_id,
    target_team_id: parsed.data.team_id,
    target_position: parsed.data.position,
    target_status: parsed.data.status,
    target_starts_on: parsed.data.starts_on || null,
    target_ends_on: parsed.data.ends_on || null
  });
  return context.redirect(redirectWithMessage(fallback, error ? "error" : "success", error?.message ?? "Team assignment saved."));
};