import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const schema = z.discriminatedUnion("action", [
  z.object({
    action: z.literal("assignment"),
    assignment_id: uuidSchema,
    status: z.enum(["interested", "assigned", "checked_in", "completed", "cancelled", "replacement_requested"]),
    note: z.string().trim().max(300).optional()
  }),
  z.object({
    action: z.literal("shift"),
    shift_id: uuidSchema,
    status: z.enum(["open", "filled", "cancelled", "completed"]),
    note: z.string().trim().max(300).optional()
  })
]);

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["volunteers.manage"]);
  if (!session) return context.redirect("/admin/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) {
    return context.redirect(redirectWithMessage("/admin/volunteers/", "error", parsed.error.issues[0]?.message ?? "Volunteer action could not be saved."));
  }

  const { error } =
    parsed.data.action === "assignment"
      ? await (session.supabase as any).rpc("update_volunteer_assignment", {
          target_assignment_id: parsed.data.assignment_id,
          target_status: parsed.data.status,
          note: parsed.data.note || "Admin volunteer update"
        })
      : await (session.supabase as any).rpc("update_volunteer_shift_status", {
          target_shift_id: parsed.data.shift_id,
          target_status: parsed.data.status,
          note: parsed.data.note || "Admin volunteer shift update"
        });

  return context.redirect(redirectWithMessage("/admin/volunteers/", error ? "error" : "success", error?.message ?? "Volunteer roster updated."));
};
