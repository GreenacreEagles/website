import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const statusMessages: Record<string, string> = {
  accepted: "Order accepted.",
  preparing: "Order marked as preparing.",
  ready_for_pickup: "Order marked ready for pickup.",
  collected: "Order marked collected.",
  cancelled: "Order cancelled."
};

const schema = z.object({
  order_id: uuidSchema,
  order_status: z.enum(["accepted", "preparing", "ready_for_pickup", "collected", "cancelled"]).optional(),
  payment_status: z.enum(["unpaid", "awaiting_payment", "paid", "partially_refunded", "refunded"]).optional(),
  reason: z.string().trim().max(500).optional(),
  return_to: z.string().trim().optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["canteen.orders.manage"]);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  const redirectTo = parsed.success && parsed.data.return_to ? parsed.data.return_to : "/admin/canteen/";
  if (!parsed.success) {
    return context.redirect(redirectWithMessage(redirectTo, "error", parsed.error.issues[0]?.message ?? "Check the order details."));
  }

  if (!parsed.data.order_status && !parsed.data.payment_status) {
    return context.redirect(redirectWithMessage(redirectTo, "error", "Choose an order or payment status."));
  }

  const { data, error } = await session.supabase.rpc("update_canteen_order_state" as any, {
    target_order_id: parsed.data.order_id,
    target_order_status: parsed.data.order_status ?? null,
    target_payment_status: parsed.data.payment_status ?? null,
    change_reason: parsed.data.reason || null
  });

  if (error) return context.redirect(redirectWithMessage(redirectTo, "error", error.message));

  const result = Array.isArray(data) ? data[0] : null;
  const newOrderStatus = result?.new_order_status ?? parsed.data.order_status;
  const notificationRecipient = result?.recipient_id ?? result?.customer_id;
  if (notificationRecipient && newOrderStatus && ["ready_for_pickup", "collected"].includes(newOrderStatus)) {
    await session.supabase.from("notifications").insert({
      recipient_id: notificationRecipient,
      title: newOrderStatus === "ready_for_pickup" ? "Canteen order ready" : "Canteen order collected",
      body:
        newOrderStatus === "ready_for_pickup"
          ? `Order ${result?.order_number ?? ""} is ready to collect from the canteen.`
          : `Order ${result?.order_number ?? ""} has been marked as collected.`
    });
  }

  const success =
    parsed.data.payment_status === "paid" && result?.issued_vouchers > 0
      ? `Payment recorded and ${result.issued_vouchers} voucher item added to wallet.`
      : parsed.data.order_status
        ? statusMessages[parsed.data.order_status]
        : "Payment status updated.";

  return context.redirect(redirectWithMessage(redirectTo, "success", success));
};
