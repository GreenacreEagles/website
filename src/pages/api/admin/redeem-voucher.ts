import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { optionalUuidSchema, redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const centsFromDollars = z.preprocess((value) => Math.round(Number(value || 0) * 100), z.number().int().min(1));
const normaliseCode = (value: string) => value.trim().replace(/^GEVOUCHER:/i, "").replace(/\s+/g, "").toUpperCase();

const schema = z.object({
  redemption_code: z.string().trim().min(4).max(80),
  venue_id: uuidSchema,
  amount: centsFromDollars,
  order_id: optionalUuidSchema,
  device_label: z.string().trim().max(120).optional(),
  return_to: z.string().trim().optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["canteen.vouchers.redeem"]);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  const redirectTo = parsed.success && parsed.data.return_to ? parsed.data.return_to : "/portal/canteen-staff/";
  if (!parsed.success) {
    return context.redirect(redirectWithMessage(redirectTo, "error", parsed.error.issues[0]?.message ?? "Check the voucher details."));
  }

  const { data, error } = await session.supabase.rpc("redeem_voucher", {
    redemption_token: normaliseCode(parsed.data.redemption_code),
    redeem_venue_id: parsed.data.venue_id,
    redeem_amount_cents: parsed.data.amount,
    redeem_order_id: parsed.data.order_id ?? undefined,
    device_label: parsed.data.device_label || "Canteen device"
  });

  if (error) return context.redirect(redirectWithMessage(redirectTo, "error", error.message));

  const result = data?.[0];
  if (result?.voucher_id) {
    const { data: voucher } = await session.supabase
      .from("voucher_issuances")
      .select("beneficiary_id")
      .eq("id", result.voucher_id)
      .single();

    if (voucher?.beneficiary_id) {
      await session.supabase.from("notifications").insert({
        recipient_id: voucher.beneficiary_id,
        title: "Voucher claimed at the canteen",
        body: "Your canteen voucher was scanned and claimed by canteen staff."
      });
    }
  }

  if (parsed.data.order_id) {
    await session.supabase
      .from("canteen_orders")
      .update({ payment_status: "paid", order_status: "accepted" })
      .eq("id", parsed.data.order_id);
  }

  return context.redirect(redirectWithMessage(redirectTo, "success", "Voucher claimed."));
};
