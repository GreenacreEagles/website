import type { APIRoute } from "astro";
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

export const GET: APIRoute = async (context) => {
  const token = new URL(context.request.url).searchParams.get("token") ?? "";
  if (token.length < 32) return context.redirect(redirectWithMessage("/portal/merchandise/", "error", "Store access token is invalid."));

  const service = createSupabaseServiceClient(context);
  const tokenHash = await hashToken(token);
  const { data, error } = await (service as any)
    .from("store_access_tokens")
    .select("id,redirect_path,expires_at,used_at,revoked_at")
    .eq("token_hash", tokenHash)
    .maybeSingle();

  if (error || !data || data.used_at || data.revoked_at || new Date(data.expires_at).getTime() <= Date.now()) {
    return context.redirect(redirectWithMessage("/portal/merchandise/", "error", "Store access has expired. Please open the store again from the portal."));
  }

  await (service as any).from("store_access_tokens").update({ used_at: new Date().toISOString() }).eq("id", data.id);
  return context.redirect(`${data.redirect_path}?portal_store=1`);
};
