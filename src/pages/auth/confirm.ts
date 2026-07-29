import type { APIRoute } from "astro";
import { createSupabaseServerClient } from "@lib/supabase/server";
import { confirmationDestination, parseEmailOtpType } from "@lib/auth/email-links";

export const prerender = false;

const invalidMessage = "This confirmation link is invalid or has expired.";
const invalidDestination = (type: string | null) =>
  type === "recovery"
    ? `/reset-password/?error=${encodeURIComponent("This password reset link is invalid or has expired. Request a new reset link.")}`
    : `/login/?error=${encodeURIComponent(invalidMessage)}`;

export const GET: APIRoute = async (context) => {
  const tokenHash = context.url.searchParams.get("token_hash");
  const type = parseEmailOtpType(context.url.searchParams.get("type"));
  if (!tokenHash || !type) return context.redirect(invalidDestination(type), 303);

  const supabase = createSupabaseServerClient(context);
  const { data, error } = await supabase.auth.verifyOtp({ token_hash: tokenHash, type });
  if (error || !data.user || !data.session) return context.redirect(invalidDestination(type), 303);

  if (type === "recovery") {
    context.cookies.set("gefc-password-recovery", data.user.id, {
      path: "/",
      httpOnly: true,
      secure: context.url.protocol === "https:",
      sameSite: "lax",
      maxAge: 15 * 60
    });
    return context.redirect(confirmationDestination(type), 303);
  }

  await supabase.auth.signOut({ scope: "local" });
  return context.redirect(confirmationDestination(type), 303);
};
