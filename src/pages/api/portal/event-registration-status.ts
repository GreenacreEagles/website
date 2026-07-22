import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  registration_id: uuidSchema,
  status: z.enum(["cancelled"])
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/events/", "error", "Registration could not be updated."));

  const { error } = await session.supabase
    .from("event_registrations")
    .update({ status: parsed.data.status })
    .eq("id", parsed.data.registration_id)
    .or(`registered_by.eq.${session.user.id},attendee_id.eq.${session.user.id}`);

  return context.redirect(redirectWithMessage("/portal/events/", error ? "error" : "success", error ? "Registration could not be updated." : "Registration cancelled."));
};
