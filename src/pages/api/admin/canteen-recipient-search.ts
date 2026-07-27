import type { APIRoute } from "astro";
import { requirePermission } from "@lib/auth/guards";

export const prerender = false;
export const GET: APIRoute = async (context) => {
  const session = await requirePermission(context, ["canteen.vouchers.manage"]);
  if (!session) {
    return new Response(JSON.stringify({ error: "Unauthorised" }), {
      status: 401,
      headers: { "content-type": "application/json", "cache-control": "no-store" },
    });
  }
  const q = context.url.searchParams.get("q")?.trim().slice(0, 80) ?? "";
  const type = context.url.searchParams.get("type") === "team" ? "team" : "member";
  const client = session.supabase as any;
  let query = type === "team"
    ? client.from("teams").select("id,name").eq("status", "active").order("name").limit(20)
    : client.from("profiles").select("id,full_name,email").eq("account_status", "active").order("full_name").limit(20);
  if (q) query = type === "team" ? query.ilike("name", `%${q}%`) : query.or(`full_name.ilike.%${q}%,email.ilike.%${q}%`);
  const { data, error } = await query;
  return new Response(JSON.stringify({ results: error ? [] : data, error: error?.message }), {
    status: error ? 400 : 200,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
};
