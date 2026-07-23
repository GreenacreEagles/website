import type { APIRoute } from "astro";
import { z } from "zod";
import { createSupabaseServiceClient } from "@lib/supabase/server";

export const prerender = false;

const payloadSchema = z.object({
  provider: z.string().trim().min(1).max(40),
  event_id: z.string().trim().min(1).max(160),
  event_type: z.string().trim().min(1).max(160).default("payment.updated"),
  payment_id: z.string().uuid().optional(),
  provider_payment_id: z.string().trim().max(160).optional(),
  status: z.enum(["succeeded", "failed", "cancelled"]),
  payload: z.record(z.string(), z.unknown()).optional()
});

const readWebhookSecret = () => import.meta.env.PAYMENT_WEBHOOK_SECRET;

const bearerToken = (authorization: string | null) => {
  if (!authorization?.startsWith("Bearer ")) return null;
  return authorization.slice("Bearer ".length).trim();
};

export const POST: APIRoute = async (context) => {
  const configuredSecret = readWebhookSecret();
  const providedSecret =
    context.request.headers.get("x-greenacre-webhook-secret") ?? bearerToken(context.request.headers.get("authorization"));

  if (!configuredSecret) {
    return new Response(JSON.stringify({ error: "Payment webhook secret is not configured." }), {
      status: 503,
      headers: { "content-type": "application/json" }
    });
  }

  if (!providedSecret || providedSecret !== configuredSecret) {
    return new Response(JSON.stringify({ error: "Unauthorised webhook." }), {
      status: 401,
      headers: { "content-type": "application/json" }
    });
  }

  const parsed = payloadSchema.safeParse(await context.request.json().catch(() => null));
  if (!parsed.success) {
    return new Response(JSON.stringify({ error: parsed.error.issues[0]?.message ?? "Invalid webhook payload." }), {
      status: 400,
      headers: { "content-type": "application/json" }
    });
  }

  const supabase = createSupabaseServiceClient(context);
  const { data, error } = await (supabase as any)
    .rpc("process_payment_webhook", {
      provider: parsed.data.provider,
      provider_event_id: parsed.data.event_id,
      event_type: parsed.data.event_type,
      provider_payment_ref: parsed.data.provider_payment_id ?? null,
      target_payment_id: parsed.data.payment_id ?? null,
      target_status: parsed.data.status,
      event_payload: parsed.data.payload ?? parsed.data
    })
    .single();

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 422,
      headers: { "content-type": "application/json" }
    });
  }

  return new Response(JSON.stringify({ ok: true, webhook: data }), {
    status: 200,
    headers: { "content-type": "application/json" }
  });
};
