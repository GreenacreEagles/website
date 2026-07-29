import { getRuntimeEnv } from "@lib/media";

export type PaymentProviderMode = "manual" | "stripe" | "square" | string;

type RuntimeContext = {
  locals?: unknown;
  request?: Request;
  url?: URL;
};

/** Club currently accepts payment at the club only. Default is always manual. */
export const getPaymentProvider = (context?: RuntimeContext): PaymentProviderMode => {
  const raw = String((context ? getRuntimeEnv(context, "PAYMENT_PROVIDER") : import.meta.env.PAYMENT_PROVIDER) ?? "manual")
    .trim()
    .toLowerCase();
  return raw || "manual";
};

export const isManualPaymentMode = (context?: RuntimeContext) => getPaymentProvider(context) === "manual";

export const onlinePaymentsEnabled = (context?: RuntimeContext) => !isManualPaymentMode(context);

/** Webhook secrets are only required when an online gateway is active. */
export const paymentWebhookRequired = (context?: RuntimeContext) => onlinePaymentsEnabled(context);

export const manualPaymentDisabledResponse = (reason = "Online payments are disabled. The club accepts payment at the club only.") =>
  new Response(JSON.stringify({ ok: false, provider: "manual", disabled: true, error: reason }), {
    status: 503,
    headers: {
      "content-type": "application/json",
      "cache-control": "private, no-store"
    }
  });
