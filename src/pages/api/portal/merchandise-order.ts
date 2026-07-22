import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  variant_id: uuidSchema,
  quantity: z.coerce.number().int().min(1).max(10),
  pickup_or_delivery: z.enum(["pickup", "delivery"]).default("pickup"),
  notes: z.string().trim().max(500).optional()
});

const orderNumber = () => `GM-${Date.now().toString(36).toUpperCase()}`;

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) {
    return context.redirect(redirectWithMessage("/portal/merchandise/", "error", parsed.error.issues[0]?.message ?? "Check the merchandise order."));
  }

  const { data: variant, error: variantError } = await session.supabase
    .from("merchandise_variants")
    .select("id,size,colour,price_cents,sale_price_cents,stock_quantity,is_active,merchandise_products(name,status)")
    .eq("id", parsed.data.variant_id)
    .single();

  if (variantError || !variant || !variant.is_active || variant.stock_quantity < parsed.data.quantity || (variant.merchandise_products as any)?.status !== "active") {
    return context.redirect(redirectWithMessage("/portal/merchandise/", "error", "That merchandise item is not available."));
  }

  const unitPrice = variant.sale_price_cents ?? variant.price_cents;
  const total = unitPrice * parsed.data.quantity;
  const productName = (variant.merchandise_products as any)?.name ?? "Club merchandise";
  const details = [productName, variant.size, variant.colour].filter(Boolean).join(" - ");

  const { error } = await session.supabase.from("merchandise_orders").insert({
    order_number: orderNumber(),
    customer_id: session.user.id,
    total_cents: total,
    status: "awaiting_payment",
    pickup_or_delivery: parsed.data.pickup_or_delivery,
    notes: `${parsed.data.quantity}x ${details}${parsed.data.notes ? `\n${parsed.data.notes}` : ""}`
  });

  return context.redirect(redirectWithMessage("/portal/merchandise/", error ? "error" : "success", error?.message ?? "Merchandise order placed."));
};
