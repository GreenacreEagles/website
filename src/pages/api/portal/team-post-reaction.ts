import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;
const schema = z.object({ team_id: uuidSchema, post_id: uuidSchema });
export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/", 303);
  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/teams/", "error", "Like could not be saved."), 303);
  const redirectPath = `/portal/teams/${parsed.data.team_id}/?tab=posts#post-${parsed.data.post_id}`;
  const table = (session.supabase as any).from("team_post_reactions");
  const { data: existing } = await table.select("id").eq("post_id", parsed.data.post_id).eq("user_id", session.user.id).maybeSingle();
  const { error } = existing
    ? await table.delete().eq("id", existing.id).eq("user_id", session.user.id)
    : await table.insert({ post_id: parsed.data.post_id, user_id: session.user.id, reaction: "like" });
  return context.redirect(redirectWithMessage(redirectPath, error ? "error" : "success", error?.message ?? (existing ? "Like removed." : "Post liked.")), 303);
};
