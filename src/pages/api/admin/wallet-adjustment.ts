import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { optionalUuidSchema, redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const centsFromDollars = z.preprocess((value) => Math.round(Number(value || 0) * 100), z.number().int().min(1).max(100000));

const schema = z.object({
  wallet_id: uuidSchema,
  amount: centsFromDollars,
  direction: z.enum(["credit", "debit"]),
  transaction_type: z.string().trim().min(3).max(80),
  description: z.string().trim().min(3).max(500),
  beneficiary_id: optionalUuidSchema,
  return_to: z.string().trim().optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["wallet.adjust"]);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  const redirectTo = parsed.success && parsed.data.return_to ? parsed.data.return_to : "/admin/wallets/";
  if (!parsed.success) {
    return context.redirect(redirectWithMessage(redirectTo, "error", parsed.error.issues[0]?.message ?? "Check the adjustment details."));
  }

  const { error } = await (session.supabase as any).rpc("adjust_wallet_balance", {
    target_wallet_id: parsed.data.wallet_id,
    amount_cents: parsed.data.amount,
    direction: parsed.data.direction,
    transaction_type: parsed.data.transaction_type,
    description: parsed.data.description,
    idempotency_key: `wallet-adjust:${session.user.id}:${parsed.data.wallet_id}:${crypto.randomUUID()}`,
    beneficiary_id: parsed.data.beneficiary_id ?? null
  });

  if (error) return context.redirect(redirectWithMessage(redirectTo, "error", error.message));

  return context.redirect(redirectWithMessage(redirectTo, "success", "Wallet adjustment recorded."));
};
