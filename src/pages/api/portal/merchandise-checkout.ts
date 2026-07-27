import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage } from "@lib/forms";
import { friendlyMerchandiseError } from "@lib/merchandise-store";

export const prerender = false;

const schema = z.object({
  request_key: z.string().regex(/^[A-Za-z0-9_-]{16,120}$/),
  payment_method: z.literal("pay_at_club"),
  notes: z.string().trim().max(500).optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect(`/login/?returnTo=${encodeURIComponent("/portal/shop/checkout/")}`);

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) {
    return context.redirect(redirectWithMessage("/portal/shop/checkout/", "error", "Review the checkout details and try again."));
  }

  const { data, error } = await (session.supabase as any).rpc("checkout_merchandise_cart", {
    request_key: parsed.data.request_key,
    target_notes: parsed.data.notes || null
  });

  if (error) {
    return context.redirect(redirectWithMessage("/portal/shop/cart/", "error", friendlyMerchandiseError(error.message)));
  }

  const created = Array.isArray(data) ? data[0] : null;
  const orderText = created?.order_number ? ` Order ${created.order_number} is now in your order history.` : "";
  return context.redirect(redirectWithMessage(
    "/portal/merchandise/",
    "success",
    `Your order has been placed. You can pay when you collect it from the club.${orderText}`
  ));
};
