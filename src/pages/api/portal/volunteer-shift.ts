import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  shift_id: uuidSchema
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/volunteers/", "error", "Select a volunteer shift."));

  const { error } = await (session.supabase as any).rpc("request_volunteer_shift", {
    target_shift_id: parsed.data.shift_id
  });

  return context.redirect(redirectWithMessage("/portal/volunteers/", error ? "error" : "success", error?.message ?? "Volunteer shift confirmed."));
};
