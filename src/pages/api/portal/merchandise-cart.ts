import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";
import { friendlyMerchandiseError } from "@lib/merchandise-store";

export const prerender = false;

const itemSchema = z.object({
  action: z.enum(["add", "set", "adjust", "remove"]),
  variant_id: uuidSchema,
  quantity: z.coerce.number().int().min(-50).max(50)
});

const safeReturnPath = (value: FormDataEntryValue | null) => {
  const path = typeof value === "string" ? value : "";
  return ["/portal/shop/", "/portal/shop/cart/", "/portal/shop/checkout/"].includes(path)
    ? path
    : "/portal/shop/cart/";
};

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect(`/login/?returnTo=${encodeURIComponent("/portal/shop/")}`);

  const form = await context.request.formData();
  const returnTo = safeReturnPath(form.get("return_to"));
  const action = String(form.get("action") ?? "");

  if (action === "clear") {
    const { error } = await (session.supabase as any).rpc("clear_merchandise_cart");
    return context.redirect(redirectWithMessage(
      returnTo,
      error ? "error" : "success",
      error ? friendlyMerchandiseError(error.message) : "Your cart has been cleared."
    ));
  }

  const parsed = itemSchema.safeParse({
    action,
    variant_id: form.get("variant_id"),
    quantity: form.get("quantity")
  });

  if (!parsed.success) {
    return context.redirect(redirectWithMessage(returnTo, "error", "Choose a valid item and quantity."));
  }

  const quantity = parsed.data.action === "remove" ? 0 : parsed.data.quantity;
  const addToExisting = parsed.data.action === "add" || parsed.data.action === "adjust";
  const { error } = await (session.supabase as any).rpc("set_merchandise_cart_item", {
    target_variant_id: parsed.data.variant_id,
    target_quantity: quantity,
    add_to_existing: addToExisting
  });

  const successMessage = parsed.data.action === "add"
    ? "Added to your cart."
    : parsed.data.action === "remove"
      ? "Item removed from your cart."
      : "Your cart has been updated.";

  return context.redirect(redirectWithMessage(
    returnTo,
    error ? "error" : "success",
    error ? friendlyMerchandiseError(error.message) : successMessage
  ));
};
