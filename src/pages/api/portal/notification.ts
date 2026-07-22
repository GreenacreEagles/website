import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  notification_id: uuidSchema.optional(),
  action: z.enum(["mark_read", "mark_all_read"])
}).refine((value) => value.action === "mark_all_read" || Boolean(value.notification_id), {
  message: "Select a notification."
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/notifications/", "error", "Notification could not be updated."));

  const readAt = new Date().toISOString();
  const query = session.supabase.from("notifications").update({ read_at: readAt }).eq("recipient_id", session.user.id);
  const { error } =
    parsed.data.action === "mark_all_read" ? await query.is("read_at", null) : await query.eq("id", parsed.data.notification_id as string);

  return context.redirect(redirectWithMessage("/portal/notifications/", error ? "error" : "success", error ? "Notification could not be updated." : "Notifications updated."));
};
