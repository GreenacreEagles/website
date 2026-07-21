import type { APIRoute } from "astro";
import { z } from "zod";
import { auPhoneSchema, redirectWithMessage } from "@lib/forms";
import { requireUser } from "@lib/auth/guards";

export const prerender = false;

const schema = z.object({
  full_name: z.string().trim().min(2).max(120),
  preferred_name: z.string().trim().max(80).optional(),
  mobile: auPhoneSchema,
  relationship_to_club: z.string().trim().max(80).optional(),
  emergency_contact_name: z.string().trim().max(120).optional(),
  emergency_contact_phone: auPhoneSchema,
  communication_email: z.string().optional(),
  communication_sms: z.string().optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/account/", "error", parsed.error.issues[0]?.message ?? "Check your details."));

  const { error } = await session.supabase
    .from("profiles")
    .update({
      full_name: parsed.data.full_name,
      preferred_name: parsed.data.preferred_name || null,
      mobile: parsed.data.mobile || null,
      relationship_to_club: parsed.data.relationship_to_club || null,
      emergency_contact_name: parsed.data.emergency_contact_name || null,
      emergency_contact_phone: parsed.data.emergency_contact_phone || null,
      communication_email: parsed.data.communication_email === "on",
      communication_sms: parsed.data.communication_sms === "on",
      onboarding_completed_at: new Date().toISOString()
    })
    .eq("id", session.user.id);

  return context.redirect(redirectWithMessage("/portal/account/", error ? "error" : "success", error ? "Profile could not be saved." : "Profile saved."));
};
