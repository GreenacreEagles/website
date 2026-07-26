import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage } from "@lib/forms";

export const prerender = false;
const schema = z.object({
  benefit_type: z.enum(["amount", "item"]),
  amount: z.coerce.number().min(0).max(10000).default(0),
  product_id: z.preprocess((value) => value === "" ? null : value, z.string().uuid().nullable()),
  expires_at: z.string().optional(),
  issue_reason: z.string().trim().max(300).optional(),
  request_key: z.string().uuid(),
});
const ids = (form: FormData, name: string) => [...new Set(form.getAll(name).map(String).filter((value) => z.string().uuid().safeParse(value).success))];

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["canteen.vouchers.manage"]);
  if (!session) return context.redirect("/admin/");
  const form = await context.request.formData();
  const parsed = schema.safeParse(Object.fromEntries(form));
  if (!parsed.success) return context.redirect(redirectWithMessage("/admin/canteen/", "error", parsed.error.issues[0]?.message ?? "Check the benefit details."));
  const { data, error } = await (session.supabase as any).rpc("issue_canteen_benefits", {
    member_ids: ids(form, "member_ids"),
    team_ids: ids(form, "team_ids"),
    benefit_type: parsed.data.benefit_type,
    amount_cents: Math.round(parsed.data.amount * 100),
    product_id: parsed.data.product_id,
    expires_at: parsed.data.expires_at ? new Date(parsed.data.expires_at).toISOString() : null,
    issue_reason: parsed.data.issue_reason || null,
    request_key: parsed.data.request_key,
  });
  const count = data?.[0]?.recipient_count ?? 0;
  return context.redirect(redirectWithMessage("/admin/canteen/", error ? "error" : "success", error?.message ?? `Benefit issued to ${count} member${count === 1 ? "" : "s"}.`));
};
