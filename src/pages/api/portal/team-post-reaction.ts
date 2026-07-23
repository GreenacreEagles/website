import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  team_id: uuidSchema,
  post_id: uuidSchema,
  reaction: z.enum(["acknowledged", "thanks", "attending", "unavailable"])
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/teams/", "error", "Reaction could not be saved."));

  const redirectPath = `/portal/teams/${parsed.data.team_id}/#post-${parsed.data.post_id}`;
  const { error } = await (session.supabase as any)
    .from("team_post_reactions")
    .upsert(
      {
        post_id: parsed.data.post_id,
        user_id: session.user.id,
        reaction: parsed.data.reaction
      },
      { onConflict: "post_id,user_id" }
    );

  return context.redirect(redirectWithMessage(redirectPath, error ? "error" : "success", error?.message ?? "Reaction saved."));
};
