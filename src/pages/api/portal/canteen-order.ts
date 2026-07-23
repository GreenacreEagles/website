import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { optionalUuidSchema, redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  product_id: uuidSchema,
  venue_id: optionalUuidSchema,
  beneficiary_id: optionalUuidSchema,
  quantity: z.coerce.number().int().min(1).max(20),
  pickup_window_start: z.string().optional(),
  special_instructions: z.string().trim().max(500).optional()
});

const orderNumber = () => `GE-${Date.now().toString(36).toUpperCase()}`;

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/canteen/", "error", parsed.error.issues[0]?.message ?? "Check the order details."));

  const { data: product, error: productError } = await session.supabase
    .from("canteen_products")
    .select("id,name,price_cents,allergen_info,is_active,is_sold_out")
    .eq("id", parsed.data.product_id)
    .single();

  if (productError || !product || !product.is_active || product.is_sold_out) {
    return context.redirect(redirectWithMessage("/portal/canteen/", "error", "That canteen item is not available."));
  }

  let recipientId = parsed.data.beneficiary_id ?? session.user.id;
  if (recipientId !== session.user.id) {
    const { data: relatedChild } = await session.supabase
      .from("family_members")
      .select("family_id,user_id,relationship,status")
      .eq("user_id", recipientId)
      .in("relationship", ["child", "player", "dependent"])
      .eq("status", "active")
      .limit(1)
      .maybeSingle();

    if (!relatedChild) {
      return context.redirect(redirectWithMessage("/portal/canteen/", "error", "You can only order for linked family members."));
    }
  }

  const subtotal = product.price_cents * parsed.data.quantity;
  const { data: order, error: orderError } = await session.supabase
    .from("canteen_orders")
    .insert({
      order_number: orderNumber(),
      venue_id: parsed.data.venue_id ?? null,
      customer_id: session.user.id,
      recipient_id: recipientId,
      pickup_window_start: parsed.data.pickup_window_start || null,
      subtotal_cents: subtotal,
      total_cents: subtotal,
      payment_status: "unpaid",
      order_status: "accepted",
      special_instructions: parsed.data.special_instructions || null
    })
    .select("id")
    .single();

  if (orderError || !order) {
    return context.redirect(redirectWithMessage("/portal/canteen/", "error", orderError?.message ?? "Order could not be created."));
  }

  const { error: itemError } = await session.supabase.from("canteen_order_items").insert({
    order_id: order.id,
    product_id: product.id,
    product_name_snapshot: product.name,
    quantity: parsed.data.quantity,
    unit_price_cents_snapshot: product.price_cents,
    line_total_cents: subtotal,
    allergen_snapshot: product.allergen_info ?? []
  });

  return context.redirect(redirectWithMessage("/portal/canteen/", itemError ? "error" : "success", itemError?.message ?? "Canteen order created."));
};
