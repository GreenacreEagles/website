import { env } from "cloudflare:workers";
import { verifyTurnstileToken, type TurnstileVerification } from "./turnstile-core";

type RuntimeContext = {
  request: Request;
};

const productionHostnames = [
  "greenacreeaglesfc.com",
  "www.greenacreeaglesfc.com"
];

const readString = (...keys: string[]) => {
  for (const key of keys) {
    const runtimeValue = (env as Record<string, unknown>)[key];
    const buildValue = import.meta.env[key];
    const value = runtimeValue ?? buildValue;
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return undefined;
};

export const getTurnstileSiteKey = () => readString("PUBLIC_TURNSTILE_SITE_KEY", "TURNSTILE_SITE_KEY");
const getTurnstileSecret = () => readString("TURNSTILE_SECRET_KEY");

const getAllowedHostnames = (requestHostname: string) => {
  const defaults = productionHostnames.includes(requestHostname)
    ? productionHostnames
    : [requestHostname];

  return new Set(
    (readString("TURNSTILE_ALLOWED_HOSTNAMES") ?? defaults.join(","))
      .split(",")
      .map((hostname) => hostname.trim().toLowerCase())
      .filter(Boolean)
  );
};

export const getTurnstileConfigurationState = () => {
  const siteKey = getTurnstileSiteKey();
  const secret = getTurnstileSecret();
  if (!siteKey || !secret) return { state: "misconfigured" as const, hasSiteKey: Boolean(siteKey), hasSecret: Boolean(secret) };
  return { state: "enabled" as const, siteKey, secret };
};

export const isTurnstileEnabled = () => getTurnstileConfigurationState().state === "enabled";

const visitorIp = (request: Request) =>
  request.headers.get("CF-Connecting-IP") ?? request.headers.get("X-Forwarded-For")?.split(",")[0]?.trim() ?? undefined;

export const verifyTurnstile = async (
  context: RuntimeContext,
  formData: FormData,
  expectedAction: string
): Promise<TurnstileVerification> => {
  const config = getTurnstileConfigurationState();
  if (config.state === "misconfigured") {
    console.error("Turnstile configuration is incomplete", {
      hasSiteKey: config.hasSiteKey,
      hasSecret: config.hasSecret,
      requestHost: new URL(context.request.url).hostname
    });
    return { success: false, error: "Sign-in verification is temporarily unavailable." };
  }

  const result = await verifyTurnstileToken({
    secret: config.secret,
    token: formData.get("cf-turnstile-response"),
    expectedAction,
    expectedHostnames: getAllowedHostnames(new URL(context.request.url).hostname.toLowerCase()),
    remoteIp: visitorIp(context.request)
  });

  if (!result.success) {
    console.warn("Turnstile verification rejected", {
      reason: result.reason,
      expectedAction,
      requestHost: new URL(context.request.url).hostname
    });
  }
  return result;
};
