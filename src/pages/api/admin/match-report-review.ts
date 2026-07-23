import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  report_id: uuidSchema,
  status: z.enum(["changes_requested", "reviewed", "closed"]),
  reviewer_notes: z.string().trim().max(2000).optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["match_reports.review"]);
  if (!session) return context.redirect("/admin/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/admin/teams/#match-reports", "error", parsed.error.issues[0]?.message ?? "Report review could not be saved."));

  const { error } = await session.supabase
    .from("match_reports")
    .update({
      status: parsed.data.status,
      reviewer_notes: parsed.data.reviewer_notes || null,
      reviewed_by: session.user.id,
      reviewed_at: new Date().toISOString()
    })
    .eq("id", parsed.data.report_id);

  return context.redirect(redirectWithMessage("/admin/teams/#match-reports", error ? "error" : "success", error?.message ?? "Match report updated."));
};
