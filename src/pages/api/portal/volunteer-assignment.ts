import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  assignment_id: uuidSchema,
  status: z.enum(["checked_in", "cancelled"])
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/volunteers/", "error", "Volunteer shift could not be updated."));

  const patch =
    parsed.data.status === "checked_in"
      ? { status: "checked_in", checked_in_at: new Date().toISOString() }
      : { status: "cancelled", checked_in_at: null };

  const { error } = await session.supabase
    .from("volunteer_assignments")
    .update(patch)
    .eq("id", parsed.data.assignment_id)
    .eq("user_id", session.user.id);

  return context.redirect(redirectWithMessage("/portal/volunteers/", error ? "error" : "success", error ? "Volunteer shift could not be updated." : "Volunteer shift updated."));
};
