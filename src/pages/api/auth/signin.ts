import type { APIRoute } from "astro";
import { z } from "zod";
import { createSupabaseServerClient } from "@lib/supabase/server";
import { redirectWithMessage } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  email: z.string().email(),
  password: z.string().min(1)
});

export const POST: APIRoute = async (context) => {
  const form = Object.fromEntries(await context.request.formData());
  const parsed = schema.safeParse(form);
  if (!parsed.success) return context.redirect(redirectWithMessage("/login/", "error", "Enter your email and password."));

  const supabase = createSupabaseServerClient(context);
  const { error } = await supabase.auth.signInWithPassword(parsed.data);
  if (error) return context.redirect(redirectWithMessage("/login/", "error", "Sign in failed. Check your details and try again."));

  return context.redirect("/portal/");
};
