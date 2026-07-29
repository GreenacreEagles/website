import type { APIRoute } from "astro";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage } from "@lib/forms";
export const prerender = false;
export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session || session.isChildAccount) return context.redirect("/login/", 303);
  const { error } = await (session.supabase as any).rpc("request_volunteer_role");
  return context.redirect(redirectWithMessage("/portal/roles/#wwcc", error ? "error" : "success", error?.message ?? "Volunteer request started. Add your WWCC details for review."), 303);
};
