import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  team_id: uuidSchema,
  title: z.string().trim().min(3).max(140),
  body: z.string().trim().max(4000).optional(),
  post_type: z.enum(["announcement", "poll", "activity"]),
  is_pinned: z.string().optional(),
  poll_options: z.string().trim().max(500).optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/teams/", "error", parsed.error.issues[0]?.message ?? "Post could not be created."));

  const redirectPath = `/portal/teams/${parsed.data.team_id}/`;
  const options = (parsed.data.poll_options ?? "")
    .split(",")
    .map((option) => option.trim())
    .filter(Boolean)
    .slice(0, 8);

  if (parsed.data.post_type === "poll" && options.length < 2) {
    return context.redirect(redirectWithMessage(redirectPath, "error", "Polls need at least two options."));
  }

  const { data: post, error: postError } = await (session.supabase as any)
    .from("team_posts")
    .insert({
      team_id: parsed.data.team_id,
      author_id: session.user.id,
      title: parsed.data.title,
      body: parsed.data.body || null,
      post_type: parsed.data.post_type,
      is_pinned: parsed.data.is_pinned === "true",
      status: "published"
    })
    .select("id")
    .single();

  if (postError || !post) {
    return context.redirect(redirectWithMessage(redirectPath, "error", postError?.message ?? "Post could not be created."));
  }

  if (parsed.data.post_type === "poll") {
    const { error: optionError } = await (session.supabase as any).from("team_poll_options").insert(
      options.map((label, index) => ({
        post_id: post.id,
        label,
        sort_order: index
      }))
    );

    if (optionError) return context.redirect(redirectWithMessage(redirectPath, "error", optionError.message));
  }

  return context.redirect(redirectWithMessage(`${redirectPath}#post-${post.id}`, "success", "Team post published."));
};
