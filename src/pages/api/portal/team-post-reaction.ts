import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";
import { clientIp, consumeRateLimit, rateLimitKey, rateLimitRedirect } from "@lib/security/rate-limit";

export const prerender = false;

const schema = z.object({
  team_id: uuidSchema,
  post_id: uuidSchema,
  desired_liked: z.enum(["true", "false"]).optional(),
  request_key: z.string().trim().min(8).max(120).optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/", 303);

  const form = Object.fromEntries(await context.request.formData());
  const parsed = schema.safeParse(form);
  if (!parsed.success) {
    return context.redirect(redirectWithMessage("/portal/teams/", "error", "Like could not be saved."), 303);
  }

  const redirectPath = `/portal/teams/${parsed.data.team_id}/?tab=posts#post-${parsed.data.post_id}`;
  const limit = await consumeRateLimit({
    supabase: session.supabase,
    limitClass: "likes",
    key: rateLimitKey([session.user.id, parsed.data.post_id, clientIp(context.request)])
  });
  if (!limit.allowed) return context.redirect(rateLimitRedirect(redirectPath, limit), 303);

  let desiredLiked: boolean;
  if (parsed.data.desired_liked) {
    desiredLiked = parsed.data.desired_liked === "true";
  } else {
    const { data: existing } = await (session.supabase as any)
      .from("team_post_reactions")
      .select("id")
      .eq("post_id", parsed.data.post_id)
      .eq("user_id", session.user.id)
      .maybeSingle();
    desiredLiked = !existing;
  }

  const { data, error } = await (session.supabase as any).rpc("set_team_post_reaction", {
    target_post_id: parsed.data.post_id,
    desired_liked: desiredLiked,
    request_key: parsed.data.request_key ?? `like:${session.user.id}:${parsed.data.post_id}`
  });

  const liked = Boolean(data?.liked ?? desiredLiked);
  return context.redirect(
    redirectWithMessage(redirectPath, error ? "error" : "success", error?.message ?? (liked ? "Post liked." : "Like removed.")),
    303
  );
};
