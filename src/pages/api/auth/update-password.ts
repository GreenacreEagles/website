import type { APIRoute } from "astro";
import { createSupabaseServerClient } from "@lib/supabase/server";
import { redirectWithMessage } from "@lib/forms";
import { validateRecoveryPasswords } from "@lib/auth/password-recovery";

export const prerender = false;

const resetRedirect = (context: Parameters<APIRoute>[0], type: "success" | "error", message: string) =>
  context.redirect(redirectWithMessage("/reset-password/", type, message), 303);

export const POST: APIRoute = async (context) => {
  const recoveryUserId = context.cookies.get("gefc-password-recovery")?.value;
  if (!recoveryUserId) {
    return resetRedirect(context, "error", "This password reset link is invalid or has expired. Request a new reset link.");
  }

  const supabase = createSupabaseServerClient(context);
  const { data: { user }, error: userError } = await supabase.auth.getUser();
  if (userError || !user || recoveryUserId !== user.id) {
    context.cookies.delete("gefc-password-recovery", { path: "/" });
    return resetRedirect(context, "error", "This password reset link is invalid or has expired. Request a new reset link.");
  }

  const parsed = validateRecoveryPasswords(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) {
    return resetRedirect(context, "error", parsed.error.issues[0]?.message ?? "Use a password of at least 8 characters.");
  }

  const { error } = await supabase.auth.updateUser({ password: parsed.data.password });
  if (error) return resetRedirect(context, "error", "Password could not be updated. Request a new reset link and try again.");

  await supabase.auth.signOut({ scope: "global" });
  context.cookies.delete("gefc-password-recovery", { path: "/" });
  return resetRedirect(context, "success", "Your password has been updated. Sign in with your new password.");
};
