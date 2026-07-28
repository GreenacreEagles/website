import type { APIRoute } from "astro";
import { createSupabaseServerClient } from "@lib/supabase/server";
import { redirectWithMessage } from "@lib/forms";
import { runSignInFlow } from "@lib/auth/signin-flow";
import { verifyTurnstile } from "@lib/security/turnstile";

export const prerender = false;

const loginRedirect = (context: Parameters<APIRoute>[0], type: "success" | "error", message: string) =>
  context.redirect(redirectWithMessage("/login/", type, message), 303);

export const GET: APIRoute = async (context) => context.redirect("/login/", 303);

export const POST: APIRoute = async (context) => {
  const correlationId = crypto.randomUUID();
  try {
    let formData: FormData;
    try {
      formData = await context.request.formData();
    } catch (cause) {
      console.error("Sign-in form parsing failed", { cause, correlationId });
      return loginRedirect(context, "error", "The sign-in form could not be read. Please try again.");
    }

    const outcome = await runSignInFlow(formData, {
      verify: () => verifyTurnstile(context, formData, "signin"),
      signIn: async (credentials) => {
        const supabase = createSupabaseServerClient(context);
        const { error } = await supabase.auth.signInWithPassword(credentials);
        return { success: !error };
      }
    });

    return outcome.success
      ? context.redirect(outcome.location, outcome.status)
      : loginRedirect(context, "error", outcome.error);
  } catch (cause) {
    console.error("Unexpected sign-in failure", { cause, correlationId });
    return loginRedirect(context, "error", `Sign in is temporarily unavailable. Reference ${correlationId}.`);
  }
};