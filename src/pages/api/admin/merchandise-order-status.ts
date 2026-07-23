import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const statusMessages: Record<string, string> = {
  paid: "Merchandise order marked paid.",
  processing: "Merchandise order marked processing.",
  awaiting_stock: "Merchandise order marked awaiting stock.",
  ready_for_pickup: "Merchandise order marked ready for pickup.",
  shipped: "Merchandise order marked shipped.",
  collected: "Merchandise order marked collected.",
  completed: "Merchandise order completed.",
  cancelled: "Merchandise order cancelled.",
  refunded: "Merchandise order refunded.",
  partially_refunded: "Merchandise order marked partially refunded."
};

const schema = z.object({
  order_id: uuidSchema,
  status: z.enum(["paid", "processing", "awaiting_stock", "ready_for_pickup", "shipped", "collected", "completed", "cancelled", "refunded", "partially_refunded"]),
  reason: z.string().trim().max(500).optional(),
  return_to: z.string().trim().optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["merchandise.manage"]);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  const redirectTo = parsed.success && parsed.data.return_to ? parsed.data.return_to : "/admin/merchandise/";
  if (!parsed.success) {
    return context.redirect(redirectWithMessage(redirectTo, "error", parsed.error.issues[0]?.message ?? "Check the order details."));
  }

  const { error } = await session.supabase.rpc("update_merchandise_order_state" as any, {
    target_order_id: parsed.data.order_id,
    target_status: parsed.data.status,
    change_reason: parsed.data.reason || null
  });

  return context.redirect(redirectWithMessage(redirectTo, error ? "error" : "success", error?.message ?? statusMessages[parsed.data.status]));
};
