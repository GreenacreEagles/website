import type { APIRoute } from "astro";
import { z } from "zod";
import { createSupabaseServerClient } from "@lib/supabase/server";
import { redirectWithMessage } from "@lib/forms";
import { verifyTurnstile } from "@lib/security/turnstile";
import { getConfiguredSiteOrigin } from "@lib/site-url";

export const prerender = false;

const schema = z.object({ email: z.string().email() });
const loginRedirect = (context: Parameters<APIRoute>[0], type: "success" | "error", message: string) =>
  context.redirect(redirectWithMessage("/login/", type, message), 303);

export const POST: APIRoute = async (context) => {
  const correlationId = crypto.randomUUID();
  try {
    let formData: FormData;
    try {
      formData = await context.request.formData();
    } catch (cause) {
      console.error("Password reset form parsing failed", { cause, correlationId });
      return loginRedirect(context, "error", "The password reset form could not be read.");
    }

    const verification = await verifyTurnstile(context, formData, "reset_password");
    if (!verification.success) return loginRedirect(context, "error", verification.error ?? "Verification failed.");

    const parsed = schema.safeParse(Object.fromEntries(formData));
    if (!parsed.success) return loginRedirect(context, "error", "Enter a valid email address.");

    const supabase = createSupabaseServerClient(context);
    const { error } = await supabase.auth.resetPasswordForEmail(parsed.data.email, {
      redirectTo: `${getConfiguredSiteOrigin(context)}/portal/account/`
    });

    if (error) return loginRedirect(context, "error", "Password reset could not be sent.");
    return loginRedirect(context, "success", "Password reset email sent.");
  } catch (cause) {
    console.error("Unexpected password reset failure", { cause, correlationId });
    return loginRedirect(context, "error", `Password reset is temporarily unavailable. Reference ${correlationId}.`);
  }
};