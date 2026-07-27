import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage } from "@lib/forms";

export const prerender = false;

const uuid = z.string().uuid();
const optionalUuid = z.preprocess((value) => value === "" ? null : value, uuid.nullable());
const optionalInteger = z.preprocess((value) => value === "" ? null : Number(value), z.number().int().min(0).nullable());
const schema = z.object({
  product_id: z.preprocess((value) => value === "" ? null : value, uuid.nullable()),
  category_id: optionalUuid,
  name: z.string().trim().min(2).max(120),
  description: z.string().trim().max(500).optional(),
  price: z.coerce.number().min(0).max(10000),
  image_object_key: z.string().trim().max(500).optional(),
  stock_quantity: optionalInteger,
  low_stock_threshold: z.coerce.number().int().min(0).max(9999),
  voucher_valid_days: z.coerce.number().int().min(1).max(365),
});

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["canteen.manage"]);
  if (!session) return context.redirect("/admin/");
  const form = await context.request.formData();
  if (form.get("intent") === "delete") {
    const productId = uuid.safeParse(form.get("product_id"));
    if (!productId.success) return context.redirect(redirectWithMessage("/admin/canteen/", "error", "Invalid product."));
    const { error } = await session.supabase.from("canteen_products" as any).delete().eq("id", productId.data);
    return context.redirect(redirectWithMessage("/admin/canteen/", error ? "error" : "success", error?.message ?? "Product deleted."));
  }
  const parsed = schema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return context.redirect(redirectWithMessage("/admin/canteen/", "error", parsed.error.issues[0]?.message ?? "Check the product details."));

  const values = {
    category_id: parsed.data.category_id,
    name: parsed.data.name,
    description: parsed.data.description || null,
    price_cents: Math.round(parsed.data.price * 100),
    image_object_key: parsed.data.image_object_key || null,
    stock_quantity: parsed.data.stock_quantity,
    low_stock_threshold: parsed.data.low_stock_threshold,
    voucher_valid_days: parsed.data.voucher_valid_days,
    dietary_info: form.getAll("dietary_info").map(String),
    allergen_info: form.getAll("allergen_info").map(String),
    is_active: form.has("is_active"),
    is_sold_out: form.has("is_sold_out"),
    fulfilment_type: "direct_order",
  };
  const query = parsed.data.product_id
    ? session.supabase.from("canteen_products" as any).update(values).eq("id", parsed.data.product_id)
    : session.supabase.from("canteen_products" as any).insert(values);
  const { error } = await query;
  return context.redirect(redirectWithMessage("/admin/canteen/", error ? "error" : "success", error?.message ?? (parsed.data.product_id ? "Product updated." : "Product created.")));
};
