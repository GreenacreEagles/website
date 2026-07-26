import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage } from "@lib/forms";

export const prerender = false;

const schema = z.object({ code: z.string().trim().min(4).max(200) });

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["shop.canteen.redeem"]);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) {
    return context.redirect(redirectWithMessage("/admin/shop/", "error", "Enter a valid collection code."));
  }

  const code = parsed.data.code.replace(/^GESHOP:/i, "");
  const { data, error } = await (session.supabase as any).rpc("redeem_shop_collection", {
    collection_code: code
  });
  const result = data?.[0];
  const message = error
    ? error.message
    : result?.result === "already_collected"
      ? `${result.order_number} was already collected.`
      : `${result?.order_number ?? "Order"} collected successfully.`;

  return context.redirect(redirectWithMessage("/admin/shop/", error ? "error" : "success", message));
};
