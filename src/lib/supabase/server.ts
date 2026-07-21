import { createServerClient } from "@supabase/ssr";
import type { Database } from "../../types/database.types";

type RuntimeContext = {
  cookies: any;
  request: Request;
  locals?: any;
};

const readEnv = (context: RuntimeContext, key: string) =>
  context.locals?.runtime?.env?.[key] ?? import.meta.env[key];

export const createSupabaseServerClient = (context: RuntimeContext) => {
  const supabaseUrl = readEnv(context, "PUBLIC_SUPABASE_URL");
  const supabaseAnonKey = readEnv(context, "PUBLIC_SUPABASE_ANON_KEY");
  const requestUrl = new URL(context.request.url);
  const secureCookies = requestUrl.protocol === "https:";

  if (!supabaseUrl || !supabaseAnonKey) {
    throw new Error("Supabase public environment variables are not configured.");
  }

  return createServerClient<Database>(supabaseUrl, supabaseAnonKey, {
    cookies: {
      getAll() {
        const header = context.request.headers.get("cookie") ?? "";
        return header
          .split(";")
          .map((cookie) => cookie.trim())
          .filter(Boolean)
          .map((cookie) => {
            const separator = cookie.indexOf("=");
            const name = separator >= 0 ? cookie.slice(0, separator) : cookie;
            const value = separator >= 0 ? decodeURIComponent(cookie.slice(separator + 1)) : "";
            return { name, value };
          });
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value, options }) => {
          context.cookies.set(name, value, {
            ...options,
            path: options.path ?? "/",
            secure: secureCookies,
            httpOnly: true,
            sameSite: "lax"
          });
        });
      }
    }
  });
};
