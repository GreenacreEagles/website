import type { APIRoute } from "astro";
import { z } from "zod";
import { createSupabaseServerClient } from "@lib/supabase/server";
import { redirectWithMessage } from "@lib/forms";
import { verifyTurnstile } from "@lib/security/turnstile";

export const prerender = false;

const schema = z
  .object({
    fullName: z.string().trim().min(2).max(120),
    email: z.string().email(),
    password: z.string().min(8),
    confirmPassword: z.string().min(8),
    terms: z.literal("on")
  })
  .refine((data) => data.password === data.confirmPassword, {
    message: "Passwords do not match.",
    path: ["confirmPassword"]
  });

export const POST: APIRoute = async (context) => {
  const formData = await context.request.formData();
  const verification = await verifyTurnstile(context, formData, "signup");
  if (!verification.success) return context.redirect(redirectWithMessage("/login/", "error", verification.error ?? "Verification failed."));

  const form = Object.fromEntries(formData);
  const parsed = schema.safeParse(form);
  if (!parsed.success) return context.redirect(redirectWithMessage("/login/", "error", "Check your signup details and try again."));

  const supabase = createSupabaseServerClient(context);
  const { error } = await supabase.auth.signUp({
    email: parsed.data.email,
    password: parsed.data.password,
    options: {
      emailRedirectTo: new URL("/portal/", context.url.origin).toString(),
      data: {
        full_name: parsed.data.fullName,
        terms_accepted: true,
        privacy_accepted: true
      }
    }
  });

  if (error) return context.redirect(redirectWithMessage("/login/", "error", "Account creation failed. The email may already be registered."));
  return context.redirect(redirectWithMessage("/login/", "success", "Account created. Check your email, then sign in."));
};
