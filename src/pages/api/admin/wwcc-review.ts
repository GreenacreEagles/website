import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  submission_id: uuidSchema,
  decision: z.enum(["approved", "rejected", "resubmission_required"]),
  reason: z.string().trim().min(5).max(1000),
  corrected_expiry_date: z.string().date().optional().or(z.literal("")),
  corrected_wwcc_number: z.string().trim().max(80).optional(),
  filter: z.enum(["pending", "approved", "expiring", "expired", "rejected", "all"]).optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["wwcc.verify"]);
  if (!session) return context.redirect("/admin/", 303);

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  const filter = parsed.success ? parsed.data.filter ?? "pending" : "pending";
  const back = `/admin/volunteers/?filter=${encodeURIComponent(filter)}`;
  if (!parsed.success) {
    return context.redirect(redirectWithMessage(back, "error", parsed.error.issues[0]?.message ?? "Check the review details."), 303);
  }

  const { error } = await (session.supabase as any).rpc("review_wwcc_submission", {
    submission_id: parsed.data.submission_id,
    decision: parsed.data.decision,
    decision_reason: parsed.data.reason,
    corrected_expiry_date: parsed.data.corrected_expiry_date || null,
    corrected_wwcc_number: parsed.data.corrected_wwcc_number || null
  });

  const successMessage =
    parsed.data.decision === "approved"
      ? "WWCC submission approved."
      : parsed.data.decision === "rejected"
        ? "WWCC submission rejected."
        : "WWCC resubmission requested.";
  return context.redirect(redirectWithMessage(back, error ? "error" : "success", error?.message ?? successMessage), 303);
};
