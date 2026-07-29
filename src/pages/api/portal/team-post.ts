import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";
import { postBodySchema, titleSchema } from "@lib/validation";
import { clientIp, consumeRateLimit, rateLimitKey, rateLimitRedirect } from "@lib/security/rate-limit";

export const prerender = false;

const schema = z.object({
  team_id: uuidSchema,
  title: titleSchema,
  body: postBodySchema.optional(),
  post_type: z.enum(["announcement", "poll"]),
  is_pinned: z.string().optional(),
  poll_options: z.string().trim().max(500).optional()
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) {
    return context.redirect(
      redirectWithMessage("/portal/teams/", "error", parsed.error.issues[0]?.message ?? "Post could not be created.")
    );
  }

  const redirectPath = `/portal/teams/${parsed.data.team_id}/`;
  const limit = await consumeRateLimit({
    supabase: session.supabase,
    limitClass: "posts",
    key: rateLimitKey([session.user.id, parsed.data.team_id, clientIp(context.request)])
  });
  if (!limit.allowed) return context.redirect(rateLimitRedirect(redirectPath, limit));

  // Fixed Yes/No polls remain the supported product behaviour.
  const options = parsed.data.post_type === "poll" ? ["Yes", "No"] : null;

  const { data, error } = await (session.supabase as any).rpc("create_team_post_with_poll", {
    target_team_id: parsed.data.team_id,
    target_title: parsed.data.title,
    target_body: parsed.data.body || null,
    target_post_type: parsed.data.post_type,
    target_is_pinned: parsed.data.is_pinned === "true",
    target_poll_options: options
  });

  if (error || !data?.post_id) {
    return context.redirect(redirectWithMessage(redirectPath, "error", error?.message ?? "Post could not be created."));
  }

  return context.redirect(redirectWithMessage(`${redirectPath}#post-${data.post_id}`, "success", "Team post added."));
};
