import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const schema = z.object({
  team_id: uuidSchema,
  post_id: uuidSchema,
  option_id: uuidSchema
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/teams/", "error", "Poll response could not be saved."));

  const redirectPath = `/portal/teams/${parsed.data.team_id}/#post-${parsed.data.post_id}`;
  const { error } = await (session.supabase as any)
    .from("team_poll_responses")
    .upsert(
      {
        post_id: parsed.data.post_id,
        option_id: parsed.data.option_id,
        user_id: session.user.id,
        respondent_id: session.user.id
      },
      { onConflict: "post_id,user_id,respondent_id" }
    );

  return context.redirect(redirectWithMessage(redirectPath, error ? "error" : "success", error?.message ?? "Poll response saved."));
};
