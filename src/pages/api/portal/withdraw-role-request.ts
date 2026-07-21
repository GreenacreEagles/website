import type { APIRoute } from "astro";
import { z } from "zod";
import { redirectWithMessage, uuidSchema } from "@lib/forms";
import { requireUser } from "@lib/auth/guards";

export const prerender = false;

const schema = z.object({
  request_id: uuidSchema,
  reason: z.string().trim().max(500).optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");
  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/role-requests/", "error", "That request could not be withdrawn."));

  const { error } = await session.supabase.rpc("withdraw_role_request", {
    target_request_id: parsed.data.request_id,
    withdrawal_reason: parsed.data.reason || undefined
  });
  return context.redirect(redirectWithMessage("/portal/role-requests/", error ? "error" : "success", error?.message ?? "Role request withdrawn."));
};
