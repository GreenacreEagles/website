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
  order_status: z.enum(["accepted", "preparing", "ready_for_pickup", "collected", "cancelled"]),
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

  const { data: existing, error: existingError } = await session.supabase
    .from("canteen_orders")
    .select("id,order_number,order_status,customer_id,recipient_id")
    .eq("id", parsed.data.order_id)
    .single();

  if (existingError || !existing) {
    return context.redirect(redirectWithMessage(redirectTo, "error", existingError?.message ?? "Order was not found."));
  }

  const { error } = await session.supabase
    .from("canteen_orders")
    .update({ order_status: parsed.data.order_status })
    .eq("id", parsed.data.order_id);

  if (error) return context.redirect(redirectWithMessage(redirectTo, "error", error.message));

  await session.supabase.from("order_status_history").insert({
    order_id: parsed.data.order_id,
    old_status: existing.order_status,
    new_status: parsed.data.order_status,
    changed_by: session.user.id
  });

  if (["ready_for_pickup", "collected"].includes(parsed.data.order_status)) {
    await session.supabase.from("notifications").insert({
      recipient_id: existing.recipient_id ?? existing.customer_id,
      title: parsed.data.order_status === "ready_for_pickup" ? "Canteen order ready" : "Canteen order collected",
      body:
        parsed.data.order_status === "ready_for_pickup"
          ? `Order ${existing.order_number} is ready to collect from the canteen.`
          : `Order ${existing.order_number} has been marked as collected.`
    });
  }

  return context.redirect(redirectWithMessage(redirectTo, "success", statusMessages[parsed.data.order_status]));
};
