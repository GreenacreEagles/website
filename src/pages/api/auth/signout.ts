import type { APIRoute } from "astro";
import { createSupabaseServerClient } from "@lib/supabase/server";

export const prerender = false;

export const POST: APIRoute = async (context) => {
  try {
    const supabase = createSupabaseServerClient(context);
    await supabase.auth.signOut();
  } catch (cause) {
    console.error("Sign-out failed", { cause });
  }
  return context.redirect("/", 303);
};