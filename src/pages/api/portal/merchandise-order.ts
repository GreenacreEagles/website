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

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) {
    return context.redirect(redirectWithMessage("/portal/merchandise/", "error", parsed.error.issues[0]?.message ?? "Check the merchandise order."));
  }

  const { data, error } = await session.supabase.rpc("create_merchandise_order" as any, {
    target_variant_id: parsed.data.variant_id,
    order_quantity: parsed.data.quantity,
    target_pickup_or_delivery: parsed.data.pickup_or_delivery,
    target_notes: parsed.data.notes || null
  });

  const created = Array.isArray(data) ? data[0] : null;
  const message = created?.order_number ? `Merchandise order ${created.order_number} placed.` : "Merchandise order placed.";

  return context.redirect(redirectWithMessage("/portal/merchandise/", error ? "error" : "success", error?.message ?? message));
};
