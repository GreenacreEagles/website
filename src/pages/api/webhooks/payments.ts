import type { APIRoute } from "astro";
import { z } from "zod";
import { createSupabaseServiceClient } from "@lib/supabase/server";
import { isManualPaymentMode, manualPaymentDisabledResponse, paymentWebhookRequired } from "@lib/payments";
import { MAX_WEBHOOK_BODY_BYTES, readJsonWithLimit } from "@lib/validation";
import { logInfo, logWarn, createRequestId } from "@lib/logging";

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
  const requestId = createRequestId();

  // Formal club policy: pay at the club only. Online gateway webhooks stay disabled.
  if (isManualPaymentMode(context)) {
    logInfo("payment_webhook.manual_disabled", {
      requestId,
      operation: "payment_webhook",
      status: 503,
      errorCode: "manual_provider"
    });
    return manualPaymentDisabledResponse(
      "Online payment webhooks are disabled while PAYMENT_PROVIDER=manual. The club accepts payment at the club only."
    );
  }

  if (!paymentWebhookRequired(context)) {
    return manualPaymentDisabledResponse();
  }

  const configuredSecret = readWebhookSecret();
  const providedSecret =
    context.request.headers.get("x-greenacre-webhook-secret") ?? bearerToken(context.request.headers.get("authorization"));

  if (!configuredSecret) {
    logWarn("payment_webhook.secret_missing", {
      requestId,
      operation: "payment_webhook",
      status: 503,
      errorCode: "webhook_secret_missing"
    });
    return new Response(JSON.stringify({ error: "Payment webhook secret is not configured." }), {
      status: 503,
      headers: { "content-type": "application/json", "cache-control": "private, no-store" }
    });
  }

  if (!providedSecret || providedSecret !== configuredSecret) {
    return new Response(JSON.stringify({ error: "Unauthorised webhook." }), {
      status: 401,
      headers: { "content-type": "application/json", "cache-control": "private, no-store" }
    });
  }

  const body = await readJsonWithLimit<unknown>(context.request, MAX_WEBHOOK_BODY_BYTES);
  if (!body.ok) return body.response;

  const parsed = payloadSchema.safeParse(body.data);
  if (!parsed.success) {
    return new Response(JSON.stringify({ error: parsed.error.issues[0]?.message ?? "Invalid webhook payload." }), {
      status: 400,
      headers: { "content-type": "application/json", "cache-control": "private, no-store" }
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
      event_payload: parsed.data.payload ?? { provider: parsed.data.provider, event_id: parsed.data.event_id, status: parsed.data.status }
    })
    .single();

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 422,
      headers: { "content-type": "application/json", "cache-control": "private, no-store" }
    });
  }

  logInfo("payment_webhook.processed", {
    requestId,
    operation: "payment_webhook",
    status: 200,
    entityId: parsed.data.payment_id
  });

  return new Response(JSON.stringify({ ok: true, webhook: data }), {
    status: 200,
    headers: { "content-type": "application/json", "cache-control": "private, no-store" }
  });
};
