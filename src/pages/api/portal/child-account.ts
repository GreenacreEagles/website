import type { APIRoute } from "astro";
import { z } from "zod";
import { createSupabaseServiceClient } from "@lib/supabase/server";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const usernameToEmail = (username: string) => `${username.toLowerCase()}@children.greenacre-eagles.local`;

const schema = z.object({
  family_id: uuidSchema,
  full_name: z.string().trim().min(2).max(120),
  username: z
    .string()
    .trim()
    .toLowerCase()
    .regex(/^[a-z0-9][a-z0-9._-]{2,40}$/),
  password: z.string().min(8).max(72),
  spending_limit: z.preprocess((value) => (value === "" ? null : Math.round(Number(value || 0) * 100)), z.number().int().min(0).nullable().optional())
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session || session.isChildAccount) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/family/", "error", parsed.error.issues[0]?.message ?? "Child account could not be created."));

  const { data: manager } = await session.supabase
    .from("family_members")
    .select("id")
    .eq("family_id", parsed.data.family_id)
    .eq("user_id", session.user.id)
    .eq("status", "active")
    .eq("can_manage", true)
    .maybeSingle();

  if (!manager) return context.redirect(redirectWithMessage("/portal/family/", "error", "You cannot manage this family group."));

  const service = createSupabaseServiceClient(context);
  const email = usernameToEmail(parsed.data.username);
  const { data: created, error: createError } = await service.auth.admin.createUser({
    email,
    password: parsed.data.password,
    email_confirm: true,
    user_metadata: {
      full_name: parsed.data.full_name,
      child_username: parsed.data.username,
      managed_child: true
    }
  });

  if (createError || !created.user) {
    return context.redirect(redirectWithMessage("/portal/family/", "error", createError?.message ?? "Child account could not be created."));
  }

  const childId = created.user.id;
  const { error: profileError } = await service.from("profiles").upsert({
    id: childId,
    full_name: parsed.data.full_name,
    relationship_to_club: "GEFC User",
    communication_email: false,
    communication_sms: false,
    onboarding_completed_at: new Date().toISOString(),
    account_status: "active"
  });

  const { error: childError } = await (service as any).from("managed_child_accounts").insert({
    child_user_id: childId,
    manager_user_id: session.user.id,
    family_id: parsed.data.family_id,
    username: parsed.data.username,
    spending_limit_cents: parsed.data.spending_limit ?? null
  });

  const { error: memberError } = await service.from("family_members").insert({
    family_id: parsed.data.family_id,
    user_id: childId,
    relationship: "child",
    status: "active",
    can_manage: false,
    can_spend: false,
    spending_limit_cents: parsed.data.spending_limit ?? null
  });

  if (!profileError && !childError && !memberError) {
    await service.from("wallet_accounts").insert({
      owner_id: childId,
      account_type: "user",
      status: "active"
    });
  }

  const error = profileError ?? childError ?? memberError;
  return context.redirect(redirectWithMessage("/portal/family/", error ? "error" : "success", error?.message ?? "Child login created."));
};
