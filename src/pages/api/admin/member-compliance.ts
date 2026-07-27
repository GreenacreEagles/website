import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;
const schema = z.object({
  user_id: uuidSchema,
  volunteer_status: z.enum(["pending", "approved", "suspended", "expired", "rejected"]),
  wwcc_status: z.enum(["not_supplied", "pending_verification", "verified", "expired", "exempt", "rejected"]),
  wwcc_number: z.string().trim().max(80).optional(),
  wwcc_expiry_date: z.string().optional(),
  wwcc_name: z.string().trim().max(160).optional(),
  reason: z.string().trim().min(10).max(1000),
  notes: z.string().trim().max(1000).optional(),
  return_to: z.string().optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["volunteers.manage", "wwcc.verify"]);
  if (!session) return context.redirect("/admin/");
  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  const fallback = parsed.success && parsed.data.return_to ? parsed.data.return_to : "/admin/users/";
  if (!parsed.success) return context.redirect(redirectWithMessage(fallback, "error", parsed.error.issues[0]?.message ?? "Check the compliance details."));
  const { error } = await session.supabase.rpc("update_member_compliance", {
    target_user_id: parsed.data.user_id,
    target_volunteer_status: parsed.data.volunteer_status,
    target_wwcc_status: parsed.data.wwcc_status,
    target_wwcc_number: parsed.data.wwcc_number || null,
    target_wwcc_expiry_date: parsed.data.wwcc_expiry_date || null,
    target_wwcc_name: parsed.data.wwcc_name || null,
    decision_reason: parsed.data.reason,
    internal_notes: parsed.data.notes || null
  });
  return context.redirect(redirectWithMessage(fallback, error ? "error" : "success", error?.message ?? "Volunteer and WWCC status updated."));
};