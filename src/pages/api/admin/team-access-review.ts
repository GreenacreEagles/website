import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  request_id: uuidSchema,
  status: z.enum(["approved", "rejected"]),
  internal_note: z.string().trim().max(800).optional(),
  return_to: z.string().optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session || session.isChildAccount) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  const redirectTo = parsed.success && parsed.data.return_to ? parsed.data.return_to : "/admin/teams/";
  if (!parsed.success) return context.redirect(redirectWithMessage("/admin/teams/", "error", parsed.error.issues[0]?.message ?? "Review could not be saved."));

  const { error } = await (session.supabase as any).rpc("review_team_access_request", {
    target_request_id: parsed.data.request_id,
    review_status: parsed.data.status,
    internal_note: parsed.data.internal_note ?? null
  });

  return context.redirect(redirectWithMessage(redirectTo, error ? "error" : "success", error?.message ?? `Team access ${parsed.data.status}.`));
};
