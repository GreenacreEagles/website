import type { APIRoute } from "astro";
import { z } from "zod";
import { optionalUuidSchema, redirectWithMessage, uuidSchema } from "@lib/forms";
import { requireUser } from "@lib/auth/guards";

export const prerender = false;

const schema = z.object({
  requested_role_id: uuidSchema,
  team_id: optionalUuidSchema,
  season_id: optionalUuidSchema,
  reason: z.string().trim().min(10).max(1000),
  experience: z.string().trim().max(1000).optional(),
  notes: z.string().trim().max(1000).optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/role-requests/", "error", parsed.error.issues[0]?.message ?? "Check the request details."));

  const { error } = await session.supabase.rpc("request_role", {
    requested_role_id: parsed.data.requested_role_id,
    target_team_id: parsed.data.team_id ?? undefined,
    target_season_id: parsed.data.season_id ?? undefined,
    request_reason: parsed.data.reason,
    request_experience: parsed.data.experience || undefined,
    request_notes: parsed.data.notes || undefined
  });

  return context.redirect(redirectWithMessage("/portal/role-requests/", error ? "error" : "success", error?.message ?? "Role request submitted."));
};
