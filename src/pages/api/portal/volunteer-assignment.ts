import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  assignment_id: uuidSchema,
  status: z.enum(["checked_in", "cancelled", "replacement_requested"])
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/volunteers/", "error", "Volunteer shift could not be updated."));

  const { error } = await (session.supabase as any).rpc("update_volunteer_assignment", {
    target_assignment_id: parsed.data.assignment_id,
    target_status: parsed.data.status,
    note: "Member portal update"
  });

  return context.redirect(redirectWithMessage("/portal/volunteers/", error ? "error" : "success", error ? "Volunteer shift could not be updated." : "Volunteer shift updated."));
};
