import type { APIRoute } from "astro";
import { z } from "zod";
import { optionalUuidSchema, redirectWithMessage, uuidSchema } from "@lib/forms";
import { requirePermission } from "@lib/auth/guards";

export const prerender = false;

const schema = z.object({
  user_id: uuidSchema,
  role_id: uuidSchema,
  team_id: optionalUuidSchema,
  season_id: optionalUuidSchema,
  starts_at: z.string().optional(),
  ends_at: z.string().optional(),
  reason: z.string().trim().min(10).max(1000),
  return_to: z.string().optional()
});

const toTimestamp = (value?: string) => (value ? new Date(value).toISOString() : undefined);

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["roles.assign"]);
  if (!session) return context.redirect("/admin/");
  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  const fallback = parsed.success && parsed.data.return_to ? parsed.data.return_to : "/admin/users/";
  if (!parsed.success) return context.redirect(redirectWithMessage(fallback, "error", parsed.error.issues[0]?.message ?? "Check the assignment details."));

  const { error } = await session.supabase.rpc("assign_user_role", {
    target_user_id: parsed.data.user_id,
    target_role_id: parsed.data.role_id,
    target_team_id: parsed.data.team_id ?? undefined,
    target_season_id: parsed.data.season_id ?? undefined,
    starts_at: toTimestamp(parsed.data.starts_at),
    ends_at: toTimestamp(parsed.data.ends_at),
    assignment_reason: parsed.data.reason
  });

  return context.redirect(redirectWithMessage(fallback, error ? "error" : "success", error?.message ?? "Role assignment saved."));
};
