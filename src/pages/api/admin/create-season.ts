import type { APIRoute } from "astro";
import { z } from "zod";
import { redirectWithMessage } from "@lib/forms";
import { requirePermission } from "@lib/auth/guards";

export const prerender = false;

const schema = z.object({
  name: z.string().trim().min(3).max(80),
  year: z.coerce.number().int().min(2000).max(2100),
  starts_on: z.string().date(),
  ends_on: z.string().date(),
  status: z.enum(["draft", "active", "completed", "archived"])
});

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["club_structure.manage"]);
  if (!session) return context.redirect("/admin/");
  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/admin/teams/", "error", "Check the season details."));
  const { error } = await session.supabase.from("seasons").insert(parsed.data);
  return context.redirect(redirectWithMessage("/admin/teams/", error ? "error" : "success", error?.message ?? "Season created."));
};
