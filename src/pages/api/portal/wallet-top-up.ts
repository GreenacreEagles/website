import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const centsFromDollars = z.preprocess((value) => Math.round(Number(value || 0) * 100), z.number().int().min(100).max(100000));

const schema = z.object({
  wallet_id: uuidSchema,
  amount: centsFromDollars,
  provider: z.string().trim().max(40).optional(),
  return_to: z.string().trim().optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  const redirectTo = parsed.success && parsed.data.return_to ? parsed.data.return_to : "/portal/vouchers/";
  if (!parsed.success) {
    return context.redirect(redirectWithMessage(redirectTo, "error", parsed.error.issues[0]?.message ?? "Check the top-up details."));
  }

  const { error } = await (session.supabase as any).rpc("create_wallet_top_up", {
    target_wallet_id: parsed.data.wallet_id,
    top_up_amount_cents: parsed.data.amount,
    provider: parsed.data.provider || "manual",
    idempotency_key: `wallet-top-up:${session.user.id}:${parsed.data.wallet_id}:${crypto.randomUUID()}`
  });

  if (error) return context.redirect(redirectWithMessage(redirectTo, "error", error.message));

  return context.redirect(redirectWithMessage(redirectTo, "success", "Top-up request created."));
};
