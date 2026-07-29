import type { APIRoute } from "astro";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage } from "@lib/forms";
export const prerender = false;
export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session || session.isChildAccount) return context.redirect("/login/", 303);
  const formData = await context.request.formData();
  const adultConfirmation = formData.get("adult_confirmation") === "true";
  if (!adultConfirmation) {
    return context.redirect(
      redirectWithMessage("/portal/roles/#wwcc", "error", "You must confirm that you are 18 years of age or older."),
      303
    );
  }
  const { error } = await (session.supabase as any).rpc("request_volunteer_role", {
    adult_confirmation: adultConfirmation
  });
  return context.redirect(redirectWithMessage("/portal/roles/#wwcc", error ? "error" : "success", error?.message ?? "Volunteer request started. Add your WWCC details for review."), 303);
};
