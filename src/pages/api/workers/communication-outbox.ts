import type { APIRoute } from "astro";
import { z } from "zod";
import { createSupabaseServiceClient } from "@lib/supabase/server";

export const prerender = false;

const claimSchema = z.object({
  action: z.literal("claim"),
  worker_id: z.string().trim().min(2).max(120),
  limit: z.number().int().min(1).max(100).default(25)
});

const completeSchema = z.object({
  action: z.literal("complete"),
  worker_id: z.string().trim().min(2).max(120),
  outbox_id: z.string().uuid(),
  external_message_id: z.string().trim().max(240).optional()
});

const failSchema = z.object({
  action: z.literal("fail"),
  worker_id: z.string().trim().min(2).max(120),
  outbox_id: z.string().uuid(),
  failure_reason: z.string().trim().min(2).max(2000),
  retry_after_seconds: z.number().int().min(30).max(86400).default(300)
});

const schema = z.discriminatedUnion("action", [claimSchema, completeSchema, failSchema]);

const readWorkerSecret = () => import.meta.env.COMMUNICATION_WORKER_SECRET;

const bearerToken = (authorization: string | null) => {
  if (!authorization?.startsWith("Bearer ")) return null;
  return authorization.slice("Bearer ".length).trim();
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" }
  });

export const POST: APIRoute = async (context) => {
  const configuredSecret = readWorkerSecret();
  const providedSecret =
    context.request.headers.get("x-greenacre-worker-secret") ?? bearerToken(context.request.headers.get("authorization"));

  if (!configuredSecret) return json({ error: "Communication worker secret is not configured." }, 503);
  if (!providedSecret || providedSecret !== configuredSecret) return json({ error: "Unauthorised worker request." }, 401);

  const parsed = schema.safeParse(await context.request.json().catch(() => null));
  if (!parsed.success) return json({ error: parsed.error.issues[0]?.message ?? "Invalid worker payload." }, 400);

  const supabase = createSupabaseServiceClient(context);

  if (parsed.data.action === "claim") {
    const { data, error } = await (supabase as any).rpc("claim_communication_outbox", {
      p_worker_id: parsed.data.worker_id,
      p_limit: parsed.data.limit
    });

    if (error) return json({ error: error.message }, 422);
    return json({ ok: true, jobs: data ?? [] });
  }

  if (parsed.data.action === "complete") {
    const { data, error } = await (supabase as any).rpc("complete_communication_outbox", {
      p_outbox_id: parsed.data.outbox_id,
      p_worker_id: parsed.data.worker_id,
      p_external_message_id: parsed.data.external_message_id ?? null
    });

    if (error) return json({ error: error.message }, 422);
    return json({ ok: Boolean(data) });
  }

  const { data, error } = await (supabase as any).rpc("fail_communication_outbox", {
    p_outbox_id: parsed.data.outbox_id,
    p_worker_id: parsed.data.worker_id,
    p_failure_reason: parsed.data.failure_reason,
    p_retry_after_seconds: parsed.data.retry_after_seconds
  });

  if (error) return json({ error: error.message }, 422);
  return json({ ok: Boolean(data) });
};
