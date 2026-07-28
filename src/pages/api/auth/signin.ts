import type { APIRoute } from "astro";
import { z } from "zod";
import { createSupabaseServerClient } from "@lib/supabase/server";
import { redirectWithMessage, safeAuthReturnPath } from "@lib/forms";
import { verifyTurnstile } from "@lib/security/turnstile";

export const prerender = false;

const schema = z.object({
  email: z.string().trim().min(3),
  password: z.string().min(1),
  returnTo: z.string().optional()
});

const usernameToEmail = (value: string) =>
  value.includes("@") ? value : `${value.toLowerCase()}@children.greenacre-eagles.local`;

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

    const verification = await verifyTurnstile(context, formData, "signin");
    if (!verification.success) return loginRedirect(context, "error", verification.error ?? "Verification failed.");

    const parsed = schema.safeParse(Object.fromEntries(formData));
    if (!parsed.success) return loginRedirect(context, "error", "Enter your email and password.");

    const supabase = createSupabaseServerClient(context);
    const { error } = await supabase.auth.signInWithPassword({
      email: usernameToEmail(parsed.data.email),
      password: parsed.data.password
    });
    if (error) return loginRedirect(context, "error", "Sign in failed. Check your details and try again.");

    return context.redirect(safeAuthReturnPath(parsed.data.returnTo), 303);
  } catch (cause) {
    console.error("Unexpected sign-in failure", { cause, correlationId });
    return loginRedirect(context, "error", `Sign in is temporarily unavailable. Reference ${correlationId}.`);
  }
};