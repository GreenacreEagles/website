import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  team_id: uuidSchema,
  requested_relationship: z.enum(["player", "parent", "guardian", "coach", "manager", "volunteer", "other"]).default("parent"),
  request_note: z.string().trim().max(500).optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");
  if (session.isChildAccount) return context.redirect("/portal/teams/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/teams/", "error", parsed.error.issues[0]?.message ?? "Request could not be submitted."));

  const { error } = await (session.supabase as any).rpc("request_team_access", {
    target_team_id: parsed.data.team_id,
    requested_relationship: parsed.data.requested_relationship,
    request_note: parsed.data.request_note ?? null
  });

  return context.redirect(redirectWithMessage("/portal/teams/", error ? "error" : "success", error?.message ?? "Team access request submitted."));
};
