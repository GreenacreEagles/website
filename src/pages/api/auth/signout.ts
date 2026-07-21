import type { APIRoute } from "astro";
import { createSupabaseServerClient } from "@lib/supabase/server";

export const prerender = false;

export const POST: APIRoute = async (context) => {
  const supabase = createSupabaseServerClient(context);
  await supabase.auth.signOut();
  return context.redirect("/");
};
