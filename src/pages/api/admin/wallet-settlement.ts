import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  payment_id: uuidSchema,
  status: z.enum(["succeeded", "failed", "cancelled"]),
  provider_payment_id: z.string().trim().max(160).optional(),
  settlement_note: z.string().trim().max(500).optional(),
  return_to: z.string().trim().optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["wallet.adjust"]);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  const redirectTo = parsed.success && parsed.data.return_to ? parsed.data.return_to : "/admin/wallets/";
  if (!parsed.success) {
    return context.redirect(redirectWithMessage(redirectTo, "error", parsed.error.issues[0]?.message ?? "Check the settlement details."));
  }

  const { error } = await (session.supabase as any).rpc("settle_wallet_top_up", {
    target_payment_id: parsed.data.payment_id,
    target_status: parsed.data.status,
    provider_payment_id: parsed.data.provider_payment_id || null,
    settlement_note: parsed.data.settlement_note || null
  });

  if (error) return context.redirect(redirectWithMessage(redirectTo, "error", error.message));

  return context.redirect(redirectWithMessage(redirectTo, "success", `Top-up ${parsed.data.status}.`));
};
