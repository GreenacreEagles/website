import type { APIRoute } from "astro";
import { z } from "zod";
import { redirectWithMessage, uuidSchema } from "@lib/forms";
import { requirePermission } from "@lib/auth/guards";

export const prerender = false;

const schema = z.object({
  assignment_id: uuidSchema,
  reason: z.string().trim().min(10).max(1000),
  return_to: z.string().optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["roles.assign"]);
  if (!session) return context.redirect("/admin/");
  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  const fallback = parsed.success && parsed.data.return_to ? parsed.data.return_to : "/admin/role-assignments/";
  if (!parsed.success) return context.redirect(redirectWithMessage(fallback, "error", "Enter a clear revocation reason."));

  const { error } = await session.supabase.rpc("revoke_user_role", {
    target_assignment_id: parsed.data.assignment_id,
    revocation_reason: parsed.data.reason
  });

  return context.redirect(redirectWithMessage(fallback, error ? "error" : "success", error?.message ?? "Role assignment revoked."));
};
