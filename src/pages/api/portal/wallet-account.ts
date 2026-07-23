import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { optionalUuidSchema, redirectWithMessage } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  owner_id: optionalUuidSchema,
  family_id: optionalUuidSchema,
  account_type: z.enum(["user", "family"]).default("user"),
  return_to: z.string().trim().optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  const redirectTo = parsed.success && parsed.data.return_to ? parsed.data.return_to : "/portal/vouchers/";
  if (!parsed.success) {
    return context.redirect(redirectWithMessage(redirectTo, "error", parsed.error.issues[0]?.message ?? "Check the wallet details."));
  }

  const { error } = await (session.supabase as any).rpc("ensure_wallet_account", {
    target_owner_id: parsed.data.owner_id ?? null,
    target_family_id: parsed.data.family_id ?? null,
    target_account_type: parsed.data.account_type
  });

  if (error) return context.redirect(redirectWithMessage(redirectTo, "error", error.message));

  return context.redirect(redirectWithMessage(redirectTo, "success", "Wallet account ready."));
};
