import type { APIRoute } from "astro";
import { requireUser } from "@lib/auth/guards";
import { createSupabaseServiceClient } from "@lib/supabase/server";
import { redirectWithMessage } from "@lib/forms";

export const prerender = false;

const hashToken = async (token: string) => {
  const bytes = new TextEncoder().encode(token);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
};

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session || session.isChildAccount) return context.redirect("/login/");

  const token = crypto.randomUUID() + crypto.randomUUID();
  const tokenHash = await hashToken(token);
  const service = createSupabaseServiceClient(context);
  const { error } = await (service as any).from("store_access_tokens").insert({
    user_id: session.user.id,
    token_hash: tokenHash,
    purpose: "merchandise_store",
    redirect_path: "/merchandise/",
    expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
  });

  if (error) return context.redirect(redirectWithMessage("/portal/merchandise/", "error", "Store access could not be created."));
  return context.redirect(`/api/merchandise/store-session?token=${encodeURIComponent(token)}`);
};
