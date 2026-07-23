import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  family_id: uuidSchema,
  email: z.string().trim().email().max(180),
  relationship: z.enum(["parent", "guardian", "carer"]).default("guardian"),
  message: z.string().trim().max(500).optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) {
    return context.redirect(redirectWithMessage("/portal/family/", "error", parsed.error.issues[0]?.message ?? "Invitation could not be created."));
  }

  const { error } = await session.supabase.rpc("invite_family_guardian" as any, {
    target_family_id: parsed.data.family_id,
    invite_email: parsed.data.email,
    invite_relationship: parsed.data.relationship,
    invite_message: parsed.data.message || null
  } as any);

  return context.redirect(redirectWithMessage("/portal/family/", error ? "error" : "success", error?.message ?? "Guardian invitation created."));
};
