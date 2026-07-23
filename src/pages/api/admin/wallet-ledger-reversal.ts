import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  entry_id: uuidSchema,
  reason: z.string().trim().min(3).max(500),
  return_to: z.string().trim().optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["wallet.adjust"]);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  const redirectTo = parsed.success && parsed.data.return_to ? parsed.data.return_to : "/admin/wallets/";
  if (!parsed.success) {
    return context.redirect(redirectWithMessage(redirectTo, "error", parsed.error.issues[0]?.message ?? "Check the reversal details."));
  }

  const { error } = await (session.supabase as any).rpc("reverse_wallet_ledger_entry", {
    target_entry_id: parsed.data.entry_id,
    reason: parsed.data.reason
  });

  if (error) return context.redirect(redirectWithMessage(redirectTo, "error", error.message));

  return context.redirect(redirectWithMessage(redirectTo, "success", "Ledger entry reversed."));
};
