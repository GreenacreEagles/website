import type { APIRoute } from "astro";
import { z } from "zod";
import { createSupabaseServerClient, createSupabaseServiceClient } from "@lib/supabase/server";
import { redirectWithMessage } from "@lib/forms";
import { verifyTurnstile } from "@lib/security/turnstile";
import { getConfiguredSiteOrigin } from "@lib/site-url";
import { clientIp, consumeRateLimit, rateLimitKey, rateLimitRedirect } from "@lib/security/rate-limit";

export const prerender = false;

const rateLimitSupabase = (context: Parameters<APIRoute>[0]) => {
  try {
    return createSupabaseServiceClient(context);
  } catch {
    return null;
  }
};

const schema = z.object({
  fullName: z.string().trim().min(2).max(120),
  email: z.string().email(),
  password: z.string().min(8),
  confirmPassword: z.string().min(8),
  terms: z.literal("on")
}).refine((data) => data.password === data.confirmPassword, {
  message: "Passwords do not match.",
  path: ["confirmPassword"]
});

const signupRedirect = (context: Parameters<APIRoute>[0], type: "success" | "error", message: string) =>
  context.redirect(redirectWithMessage("/signup/", type, message), 303);

export const POST: APIRoute = async (context) => {
  const correlationId = crypto.randomUUID();
  try {
    let formData: FormData;
    try {
      formData = await context.request.formData();
    } catch (cause) {
      console.error("Signup form parsing failed", { cause, correlationId });
      return signupRedirect(context, "error", "The account form could not be read. Please try again.");
    }

    const normalizedIdentifier = String(formData.get("email") ?? "").trim().toLowerCase();
    const rateLimit = await consumeRateLimit({
      supabase: rateLimitSupabase(context),
      limitClass: "auth",
      key: rateLimitKey([normalizedIdentifier, clientIp(context.request)])
    });
    if (!rateLimit.allowed) {
      return context.redirect(rateLimitRedirect("/signup/", rateLimit), 303);
    }

    const verification = await verifyTurnstile(context, formData, "signup");
    if (!verification.success) return signupRedirect(context, "error", verification.error ?? "Verification failed.");

    const parsed = schema.safeParse(Object.fromEntries(formData));
    if (!parsed.success) return signupRedirect(context, "error", "Check your account details and try again.");

    const supabase = createSupabaseServerClient(context);
    const { error } = await supabase.auth.signUp({
      email: parsed.data.email,
      password: parsed.data.password,
      options: {
        emailRedirectTo: `${getConfiguredSiteOrigin(context)}/auth/confirm`,
        data: {
          full_name: parsed.data.fullName,
          terms_accepted: true,
          privacy_accepted: true
        }
      }
    });

    if (error) return signupRedirect(context, "error", "Account creation could not be completed. Check your details and try again.");
    return signupRedirect(context, "success", "Account created. Check your email, then sign in.");
  } catch (cause) {
    console.error("Unexpected signup failure", { cause, correlationId });
    return signupRedirect(context, "error", `Account creation is temporarily unavailable. Reference ${correlationId}.`);
  }
};