import type { APIRoute } from "astro";
import { z } from "zod";
import { createSupabaseServiceClient } from "@lib/supabase/server";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";
import { childUsernameSchema, nameSchema } from "@lib/validation";
import { clientIp, consumeRateLimit, rateLimitKey, rateLimitRedirect } from "@lib/security/rate-limit";
import { logError, logInfo, createRequestId } from "@lib/logging";

export const prerender = false;

const usernameToEmail = (username: string) => `${username.toLowerCase()}@children.greenacre-eagles.local`;

const schema = z.object({
  family_id: uuidSchema,
  full_name: nameSchema,
  username: childUsernameSchema,
  password: z.string().min(8).max(72),
  spending_limit: z.preprocess(
    (value) => (value === "" || value == null ? null : Math.round(Number(value || 0) * 100)),
    z.number().int().min(0).max(1_000_000).nullable().optional()
  ),
  idempotency_key: z.string().trim().min(8).max(120).optional()
});

const markProvisioningFailed = async (
  service: ReturnType<typeof createSupabaseServiceClient>,
  idempotencyKey: string,
  managerId: string,
  familyId: string,
  username: string,
  fullName: string,
  spendingLimit: number | null | undefined,
  authUserId: string | null,
  failureCode: string,
  failureDetail: string
) => {
  try {
    await (service as any).from("child_account_provisioning").upsert(
      {
        idempotency_key: idempotencyKey,
        manager_user_id: managerId,
        family_id: familyId,
        username,
        full_name: fullName,
        spending_limit_cents: spendingLimit ?? null,
        auth_user_id: authUserId,
        status: authUserId ? "failed" : "failed",
        failure_code: failureCode,
        failure_detail: failureDetail.slice(0, 400),
        updated_at: new Date().toISOString()
      },
      { onConflict: "idempotency_key" }
    );
  } catch {
    // Best-effort status tracking only.
  }
};

const compensateAuthUser = async (
  service: ReturnType<typeof createSupabaseServiceClient>,
  authUserId: string,
  requestId: string
) => {
  const { error } = await service.auth.admin.deleteUser(authUserId);
  if (error) {
    // Disable login if hard delete fails so the orphan cannot authenticate.
    await service.auth.admin.updateUserById(authUserId, {
      ban_duration: "876600h",
      user_metadata: { managed_child: true, provisioning_failed: true }
    });
    logError("child_provisioning.compensation_partial", {
      requestId,
      operation: "child_provisioning.compensate",
      entityId: authUserId,
      errorCode: "auth_delete_failed"
    });
    return false;
  }
  return true;
};

export const POST: APIRoute = async (context) => {
  const requestId = createRequestId();
  const session = await requireUser(context);
  if (!session || session.isChildAccount) return context.redirect("/login/");

  const limit = await consumeRateLimit({
    supabase: session.supabase,
    limitClass: "child_account",
    key: rateLimitKey([session.user.id, clientIp(context.request)])
  });
  if (!limit.allowed) {
    return context.redirect(rateLimitRedirect("/portal/family/", limit), 303);
  }

  const form = Object.fromEntries(await context.request.formData());
  const parsed = schema.safeParse(form);
  if (!parsed.success) {
    return context.redirect(
      redirectWithMessage("/portal/family/", "error", parsed.error.issues[0]?.message ?? "Child account could not be created."),
      303
    );
  }

  const idempotencyKey =
    parsed.data.idempotency_key ??
    `child:${session.user.id}:${parsed.data.family_id}:${parsed.data.username}`;

  const { data: manager } = await session.supabase
    .from("family_members")
    .select("id")
    .eq("family_id", parsed.data.family_id)
    .eq("user_id", session.user.id)
    .eq("status", "active")
    .eq("can_manage", true)
    .maybeSingle();

  if (!manager) {
    return context.redirect(redirectWithMessage("/portal/family/", "error", "You cannot manage this family group."), 303);
  }

  const service = createSupabaseServiceClient(context);

  // Idempotent short-circuit: completed provisioning for this key/username.
  const { data: existingChild } = await (service as any)
    .from("managed_child_accounts")
    .select("id,child_user_id,username")
    .eq("username", parsed.data.username)
    .maybeSingle();

  if (existingChild) {
    logInfo("child_provisioning.idempotent_hit", {
      requestId,
      operation: "child_provisioning",
      actorId: session.user.id,
      entityId: existingChild.child_user_id
    });
    return context.redirect(redirectWithMessage("/portal/family/", "success", "Child login already exists."), 303);
  }

  const email = usernameToEmail(parsed.data.username);
  let authUserId: string | null = null;

  const { data: created, error: createError } = await service.auth.admin.createUser({
    email,
    password: parsed.data.password,
    email_confirm: true,
    user_metadata: {
      full_name: parsed.data.full_name,
      child_username: parsed.data.username,
      managed_child: true,
      provisioning_key: idempotencyKey
    }
  });

  if (createError || !created.user) {
    const message = createError?.message ?? "Child account could not be created.";
    const duplicate = /already|registered|exists/i.test(message);
    await markProvisioningFailed(
      service,
      idempotencyKey,
      session.user.id,
      parsed.data.family_id,
      parsed.data.username,
      parsed.data.full_name,
      parsed.data.spending_limit,
      null,
      duplicate ? "auth_duplicate" : "auth_create_failed",
      message
    );
    logError("child_provisioning.auth_failed", {
      requestId,
      operation: "child_provisioning",
      actorId: session.user.id,
      errorCode: duplicate ? "auth_duplicate" : "auth_create_failed"
    });
    return context.redirect(
      redirectWithMessage(
        "/portal/family/",
        "error",
        duplicate ? "That child username is already in use." : "Child account could not be created."
      ),
      303
    );
  }

  authUserId = created.user.id;

  const { data: provisioned, error: provisionError } = await (service as any).rpc("complete_child_account_provisioning", {
    target_auth_user_id: authUserId,
    target_manager_user_id: session.user.id,
    target_family_id: parsed.data.family_id,
    target_username: parsed.data.username,
    target_full_name: parsed.data.full_name,
    target_spending_limit_cents: parsed.data.spending_limit ?? null,
    target_idempotency_key: idempotencyKey
  });

  if (provisionError || !provisioned?.ok) {
    const compensated = await compensateAuthUser(service, authUserId, requestId);
    await markProvisioningFailed(
      service,
      idempotencyKey,
      session.user.id,
      parsed.data.family_id,
      parsed.data.username,
      parsed.data.full_name,
      parsed.data.spending_limit,
      authUserId,
      "db_provision_failed",
      provisionError?.message ?? "provisioning_rpc_failed"
    );
    logError("child_provisioning.db_failed", {
      requestId,
      operation: "child_provisioning",
      actorId: session.user.id,
      entityId: authUserId,
      errorCode: compensated ? "db_failed_compensated" : "db_failed_orphan"
    });
    return context.redirect(
      redirectWithMessage(
        "/portal/family/",
        "error",
        provisionError?.message ?? "Child account could not be completed. Please try again."
      ),
      303
    );
  }

  if (!provisioned.wallet_account_id) {
    const compensated = await compensateAuthUser(service, authUserId, requestId);
    await markProvisioningFailed(
      service,
      idempotencyKey,
      session.user.id,
      parsed.data.family_id,
      parsed.data.username,
      parsed.data.full_name,
      parsed.data.spending_limit,
      authUserId,
      "wallet_missing",
      "wallet_account_id missing after provisioning"
    );
    logError("child_provisioning.wallet_missing", {
      requestId,
      operation: "child_provisioning",
      actorId: session.user.id,
      entityId: authUserId,
      errorCode: compensated ? "wallet_missing_compensated" : "wallet_missing_orphan"
    });
    return context.redirect(redirectWithMessage("/portal/family/", "error", "Child wallet could not be created."), 303);
  }

  logInfo("child_provisioning.completed", {
    requestId,
    operation: "child_provisioning",
    actorId: session.user.id,
    entityId: authUserId,
    status: 200
  });

  return context.redirect(redirectWithMessage("/portal/family/", "success", "Child login created."), 303);
};
