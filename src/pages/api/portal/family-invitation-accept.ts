import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  invitation_id: uuidSchema
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/family/", "error", "Invitation could not be accepted."));

  const { error } = await session.supabase.rpc("accept_family_invitation" as any, {
    target_invitation_id: parsed.data.invitation_id
  } as any);

  return context.redirect(redirectWithMessage("/portal/family/", error ? "error" : "success", error?.message ?? "Family invitation accepted."));
};
