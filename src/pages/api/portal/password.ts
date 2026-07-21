import type { APIRoute } from "astro";
import { z } from "zod";
import { redirectWithMessage } from "@lib/forms";
import { requireUser } from "@lib/auth/guards";

export const prerender = false;

const schema = z
  .object({
    password: z.string().min(8),
    confirmPassword: z.string().min(8)
  })
  .refine((data) => data.password === data.confirmPassword, { path: ["confirmPassword"] });

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");
  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/account/", "error", "Passwords must match and be at least 8 characters."));
  const { error } = await session.supabase.auth.updateUser({ password: parsed.data.password });
  return context.redirect(redirectWithMessage("/portal/account/", error ? "error" : "success", error ? "Password could not be updated." : "Password updated."));
};
