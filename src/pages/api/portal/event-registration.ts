import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  event_id: uuidSchema
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/events/", "error", "Select an event to register."));

  const { error } = await session.supabase.from("event_registrations").insert({
    event_id: parsed.data.event_id,
    attendee_id: session.user.id,
    registered_by: session.user.id,
    status: "interest"
  });

  return context.redirect(redirectWithMessage("/portal/events/", error ? "error" : "success", error?.message ?? "Event registration recorded."));
};
