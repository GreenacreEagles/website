import { createBrowserClient } from "@supabase/ssr";
import type { Database } from "../../types/database.types";

const supabaseUrl = import.meta.env.PUBLIC_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.PUBLIC_SUPABASE_ANON_KEY;

export const isSupabaseConfigured = Boolean(supabaseUrl && supabaseAnonKey);

export const createSupabaseBrowserClient = () => {
  if (!isSupabaseConfigured) return null;
  return createBrowserClient<Database>(supabaseUrl, supabaseAnonKey);
};
