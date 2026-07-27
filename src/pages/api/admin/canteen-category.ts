import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage } from "@lib/forms";

export const prerender = false;
const schema = z.object({
  category_id: z.preprocess((value) => value === "" ? null : value, z.string().uuid().nullable()),
  name: z.string().trim().min(2).max(80),
  position: z.coerce.number().int().min(1),
});

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["canteen.manage"]);
  if (!session) return context.redirect("/admin/");
  const form = await context.request.formData();
  if (form.get("intent") === "delete") {
    const categoryId = z.string().uuid().safeParse(form.get("category_id"));
    if (!categoryId.success) return context.redirect(redirectWithMessage("/admin/canteen/", "error", "Invalid category."));
    const { error } = await session.supabase.from("canteen_categories").delete().eq("id", categoryId.data);
    return context.redirect(redirectWithMessage("/admin/canteen/", error ? "error" : "success", error?.message ?? "Category deleted."));
  }
  const parsed = schema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return context.redirect(redirectWithMessage("/admin/canteen/", "error", parsed.error.issues[0]?.message ?? "Check the category."));
  const { error } = await (session.supabase as any).rpc("save_canteen_category", {
    target_category_id: parsed.data.category_id,
    category_name: parsed.data.name,
    target_position: parsed.data.position,
    category_active: form.has("is_active"),
  });
  return context.redirect(redirectWithMessage("/admin/canteen/", error ? "error" : "success", error?.message ?? "Category saved."));
};
