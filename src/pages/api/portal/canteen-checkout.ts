import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";
import { friendlyCanteenError } from "@lib/canteen-store";
import { clientIp, consumeRateLimit, rateLimitKey, rateLimitRedirect } from "@lib/security/rate-limit";

export const prerender = false;
const optionalUuid = z.preprocess((value) => value === "" || value == null ? null : value, uuidSchema.nullable());
const schema = z.object({
  request_key: z.string().regex(/^[A-Za-z0-9_-]{16,120}$/),
  wallet_id: optionalUuid,
  wallet_cents: z.coerce.number().int().min(0).max(1_000_000),
  notes: z.string().trim().max(500).optional(),
  voucher_ids: z.array(uuidSchema).max(50)
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect(`/login/?returnTo=${encodeURIComponent("/portal/canteen/shop/checkout/")}`);
  const limit = await consumeRateLimit({
    supabase: session.supabase,
    limitClass: "checkout",
    key: rateLimitKey([session.user.id, clientIp(context.request)])
  });
  if (!limit.allowed) return context.redirect(rateLimitRedirect("/portal/canteen/shop/checkout/", limit));
  const form = await context.request.formData();
  const parsed = schema.safeParse({
    request_key: form.get("request_key"), wallet_id: form.get("wallet_id"),
    wallet_cents: form.get("wallet_cents") ?? 0,
    notes: form.get("notes"), voucher_ids: form.getAll("voucher_ids")
  });
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/canteen/shop/checkout/", "error", "Review the checkout details and try again."));
  const { data, error } = await (session.supabase as any).rpc("checkout_canteen_cart", {
    request_key: parsed.data.request_key, target_wallet_id: parsed.data.wallet_id,
    target_wallet_cents: parsed.data.wallet_cents, target_voucher_ids: parsed.data.voucher_ids,
    target_notes: parsed.data.notes || null
  });
  if (error) return context.redirect(redirectWithMessage("/portal/canteen/shop/cart/", "error", friendlyCanteenError(error.message)));
  const order = Array.isArray(data) ? data[0] : null;
  const payment = order?.amount_due_cents > 0
    ? "Pay the remaining balance when you collect it from the club."
    : "Your vouchers and canteen credit covered the full order.";
  return context.redirect(redirectWithMessage("/portal/canteen/", "success",
    `Your canteen order has been placed. ${payment}${order?.order_number ? ` Order ${order.order_number} is in your order history.` : ""}`));
};
