import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";
import { friendlyCanteenError } from "@lib/canteen-store";

export const prerender = false;
const itemSchema = z.object({
  action: z.enum(["add", "set", "adjust", "remove"]),
  product_id: uuidSchema,
  quantity: z.coerce.number().int().min(-50).max(50)
});
const safeReturnPath = (value: FormDataEntryValue | null) => {
  const path = typeof value === "string" ? value : "";
  return ["/portal/canteen/shop/", "/portal/canteen/shop/cart/", "/portal/canteen/shop/checkout/"].includes(path)
    ? path : "/portal/canteen/shop/cart/";
};

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect(`/login/?returnTo=${encodeURIComponent("/portal/canteen/shop/")}`);
  const form = await context.request.formData();
  const returnTo = safeReturnPath(form.get("return_to"));
  const action = String(form.get("action") ?? "");
  if (action === "clear") {
    const { error } = await (session.supabase as any).rpc("clear_canteen_cart");
    return context.redirect(redirectWithMessage(returnTo, error ? "error" : "success",
      error ? friendlyCanteenError(error.message) : "Your canteen cart has been cleared."));
  }
  const parsed = itemSchema.safeParse({ action, product_id: form.get("product_id"), quantity: form.get("quantity") });
  if (!parsed.success) return context.redirect(redirectWithMessage(returnTo, "error", "Choose a valid item and quantity."));
  const quantity = parsed.data.action === "remove" ? 0 : parsed.data.quantity;
  const { error } = await (session.supabase as any).rpc("set_canteen_cart_item", {
    target_product_id: parsed.data.product_id, target_quantity: quantity,
    add_to_existing: parsed.data.action === "add" || parsed.data.action === "adjust"
  });
  const message = parsed.data.action === "add" ? "Added to your canteen cart."
    : parsed.data.action === "remove" ? "Item removed from your cart." : "Your canteen cart has been updated.";
  return context.redirect(redirectWithMessage(returnTo, error ? "error" : "success",
    error ? friendlyCanteenError(error.message) : message));
};
