import type { APIRoute } from "astro";
import { z } from "zod";
import { redirectWithMessage, uuidSchema } from "@lib/forms";
import { requirePermission } from "@lib/auth/guards";

export const prerender = false;

const schema = z.object({
  request_id: uuidSchema,
  decision: z.enum(["under_review", "approved", "rejected"]),
  review_reason: z.string().trim().min(10).max(1000),
  starts_at: z.string().optional(),
  ends_at: z.string().optional()
});

const toTimestamp = (value?: string) => (value ? new Date(value).toISOString() : undefined);

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["roles.review"]);
  if (!session) return context.redirect("/admin/");
  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/admin/role-requests/", "error", parsed.error.issues[0]?.message ?? "Check the review details."));

  const { error } = await session.supabase.rpc("review_role_request", {
    target_request_id: parsed.data.request_id,
    decision: parsed.data.decision,
    review_reason: parsed.data.review_reason,
    assignment_starts_at: toTimestamp(parsed.data.starts_at),
    assignment_ends_at: toTimestamp(parsed.data.ends_at)
  });

  return context.redirect(redirectWithMessage("/admin/role-requests/", error ? "error" : "success", error?.message ?? "Request review saved."));
};
