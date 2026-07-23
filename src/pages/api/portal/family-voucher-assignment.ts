import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  voucher_id: uuidSchema,
  child_id: uuidSchema,
  note: z.string().trim().max(300).optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) {
    return context.redirect(redirectWithMessage("/portal/family/", "error", parsed.error.issues[0]?.message ?? "Voucher could not be assigned."));
  }

  const { error } = await session.supabase.rpc("assign_voucher_to_family_member" as any, {
    target_voucher_id: parsed.data.voucher_id,
    target_child_id: parsed.data.child_id,
    assignment_note: parsed.data.note || null
  } as any);

  return context.redirect(redirectWithMessage("/portal/family/", error ? "error" : "success", error?.message ?? "Voucher assigned to family member."));
};
