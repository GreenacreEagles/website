import type { APIRoute } from "astro";
import { z } from "zod";
import { createSupabaseServerClient } from "@lib/supabase/server";
import { redirectWithMessage } from "@lib/forms";

export const prerender = false;

const schema = z.object({ email: z.string().email() });

export const POST: APIRoute = async (context) => {
  const form = Object.fromEntries(await context.request.formData());
  const parsed = schema.safeParse(form);
  if (!parsed.success) return context.redirect(redirectWithMessage("/login/", "error", "Enter a valid email address."));

  const supabase = createSupabaseServerClient(context);
  const { error } = await supabase.auth.resetPasswordForEmail(parsed.data.email, {
    redirectTo: new URL("/portal/account/", context.url.origin).toString()
  });

  if (error) return context.redirect(redirectWithMessage("/login/", "error", "Password reset could not be sent."));
  return context.redirect(redirectWithMessage("/login/", "success", "Password reset email sent."));
};
