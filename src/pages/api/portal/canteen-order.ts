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

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/canteen/", "error", parsed.error.issues[0]?.message ?? "Check the order details."));

  const { data, error } = await session.supabase.rpc("create_canteen_order" as any, {
    target_product_id: parsed.data.product_id,
    target_venue_id: parsed.data.venue_id ?? null,
    target_beneficiary_id: parsed.data.beneficiary_id ?? null,
    order_quantity: parsed.data.quantity,
    target_pickup_window_start: parsed.data.pickup_window_start || null,
    target_special_instructions: parsed.data.special_instructions || null
  });

  const created = Array.isArray(data) ? data[0] : null;
  const message =
    created?.payment_status === "paid"
      ? "Canteen order created and marked paid."
      : "Canteen order created. Pay at the canteen or with the configured online payment flow when available.";

  return context.redirect(redirectWithMessage("/portal/canteen/", error ? "error" : "success", error?.message ?? message));
};
