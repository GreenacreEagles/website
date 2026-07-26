import type { APIRoute } from "astro";
import { z } from "zod";
import { createSupabaseServerClient } from "@lib/supabase/server";
import { redirectWithMessage } from "@lib/forms";
import { verifyTurnstile } from "@lib/security/turnstile";

export const prerender = false;

const schema = z.object({
  email: z.string().trim().min(3),
  password: z.string().min(1),
  returnTo: z.string().optional()
});

const usernameToEmail = (value: string) =>
  value.includes("@") ? value : `${value.toLowerCase()}@children.greenacre-eagles.local`;

export const POST: APIRoute = async (context) => {
  const formData = await context.request.formData();
  const verification = await verifyTurnstile(context, formData, "signin");
  if (!verification.success) return context.redirect(redirectWithMessage("/login/", "error", verification.error ?? "Verification failed."));

  const form = Object.fromEntries(formData);
  const parsed = schema.safeParse(form);
  if (!parsed.success) return context.redirect(redirectWithMessage("/login/", "error", "Enter your email and password."));

  const supabase = createSupabaseServerClient(context);
  const { error } = await supabase.auth.signInWithPassword({
    email: usernameToEmail(parsed.data.email),
    password: parsed.data.password
  });
  if (error) return context.redirect(redirectWithMessage("/login/", "error", "Sign in failed. Check your details and try again."));

  const requested = parsed.data.returnTo ?? "/portal/";
  const returnTo = requested.startsWith("/") && !requested.startsWith("//") ? requested : "/portal/";
  return context.redirect(returnTo);
};
