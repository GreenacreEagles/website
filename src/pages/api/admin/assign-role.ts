import type { APIRoute } from "astro";
import { z } from "zod";
import { redirectWithMessage, uuidSchema } from "@lib/forms";
import { requirePermission } from "@lib/auth/guards";

export const prerender = false;

const schema = z.object({
  user_id: uuidSchema,
  role_ids: z.array(uuidSchema).min(1, "Select at least one role.").max(20),
  reason: z.string().trim().min(10).max(1000),
  return_to: z.string().optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["roles.assign", "roles.manage"]);
  if (!session) return context.redirect("/admin/");
  const formData = await context.request.formData();
  const parsed = schema.safeParse({
    ...Object.fromEntries(formData),
    role_ids: [...new Set(formData.getAll("role_ids").map(String))]
  });
  const fallback = parsed.success && parsed.data.return_to ? parsed.data.return_to : "/admin/users/";
  if (!parsed.success) return context.redirect(redirectWithMessage(fallback, "error", parsed.error.issues[0]?.message ?? "Check the assignment details."));

  for (const roleId of parsed.data.role_ids) {
    const { error } = await session.supabase.rpc("assign_user_role", {
      target_user_id: parsed.data.user_id,
      target_role_id: roleId,
      target_team_id: undefined,
      target_season_id: undefined,
      starts_at: undefined,
      ends_at: undefined,
      assignment_reason: parsed.data.reason
    });
    if (error) return context.redirect(redirectWithMessage(fallback, "error", error.message));
  }

  const count = parsed.data.role_ids.length;
  return context.redirect(redirectWithMessage(fallback, "success", count === 1 ? "Role assigned." : `${count} roles assigned.`));
};
