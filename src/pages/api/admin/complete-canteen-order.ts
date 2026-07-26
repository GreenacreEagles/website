import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage } from "@lib/forms";

export const prerender = false;
const schema = z.object({
  order_id: z.preprocess((value) => value === "" ? null : value, z.string().uuid().nullable()),
  order_code: z.string().trim().max(80).optional(),
  source: z.enum(["manual", "qr", "voucher"]).default("manual"),
}).refine((value) => value.order_id || (value.order_code && value.order_code.length >= 8), "Enter an order code.");
export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["canteen.orders.manage", "canteen.vouchers.redeem"]);
  if (!session) return context.redirect("/admin/");
  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/admin/canteen/", "error", "Invalid order."));
  const { error } = parsed.data.order_id
    ? await (session.supabase as any).rpc("complete_canteen_order", { target_order_id: parsed.data.order_id, completion_source: parsed.data.source })
    : await (session.supabase as any).rpc("complete_canteen_order_by_code", { order_code: parsed.data.order_code });
  return context.redirect(redirectWithMessage("/admin/canteen/", error ? "error" : "success", error?.message ?? "Order completed."));
};
