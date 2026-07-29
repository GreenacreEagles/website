import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage } from "@lib/forms";

export const prerender = false;
const schema = z.object({ name: z.string().trim().min(2).max(120) });

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session || session.isChildAccount) return context.redirect("/login/", 303);
  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/family/", "error", "Enter a family group name."), 303);
  const { error } = await (session.supabase as any).rpc("create_family_group", { group_name: parsed.data.name });
  return context.redirect(redirectWithMessage("/portal/family/", error ? "error" : "success", error?.message ?? "Family group created."), 303);
};
