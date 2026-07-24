import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  code: z.string().trim().min(4).max(80),
  amount: z.preprocess((value) => Math.round(Number(value || 0) * 100), z.number().int().min(1)),
  description: z.string().trim().max(200).optional(),
  return_to: z.string().optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["canteen.orders.manage", "wallet.adjust"]);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  const redirectTo = parsed.success && parsed.data.return_to ? parsed.data.return_to : "/admin/canteen/";
  if (!parsed.success) return context.redirect(redirectWithMessage("/admin/canteen/", "error", parsed.error.issues[0]?.message ?? "Wallet purchase could not be processed."));

  const code = parsed.data.code.replace(/^GEWALLET:/i, "").trim().toUpperCase();
  const { error } = await (session.supabase as any).rpc("process_wallet_qr_purchase", {
    wallet_display_code: code,
    purchase_amount_cents: parsed.data.amount,
    purchase_description: parsed.data.description || "Canteen wallet purchase",
    idempotency_key: `canteen-wallet:${session.user.id}:${code}:${crypto.randomUUID()}`
  });

  return context.redirect(redirectWithMessage(redirectTo, error ? "error" : "success", error?.message ?? "Wallet purchase processed."));
};
