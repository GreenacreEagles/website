export type TurnstileFailureReason =
  | "missing-token"
  | "invalid-token"
  | "expired-token"
  | "action-mismatch"
  | "hostname-mismatch"
  | "siteverify-unavailable";

export type TurnstileVerification = {
  success: boolean;
  error?: string;
  reason?: TurnstileFailureReason;
};

type SiteverifyResponse = {
  success?: boolean;
  action?: string;
  hostname?: string;
  "error-codes"?: string[];
};

type VerifyOptions = {
  secret: string;
  token: FormDataEntryValue | null;
  expectedAction: string;
  expectedHostnames: ReadonlySet<string>;
  remoteIp?: string;
  fetcher?: typeof fetch;
};

export const verifyTurnstileToken = async ({
  secret,
  token,
  expectedAction,
  expectedHostnames,
  remoteIp,
  fetcher = fetch
}: VerifyOptions): Promise<TurnstileVerification> => {
  if (typeof token !== "string" || token.length === 0 || token.length > 2048) {
    return { success: false, reason: "missing-token", error: "Please complete the verification check and try again." };
  }

  const body = new URLSearchParams({ secret, response: token });
  if (remoteIp) body.set("remoteip", remoteIp);

  try {
    const response = await fetcher("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body,
      signal: AbortSignal.timeout(10_000)
    });
    if (!response.ok) {
      return { success: false, reason: "siteverify-unavailable", error: "Verification is temporarily unavailable. Please try again." };
    }

    const result = await response.json() as SiteverifyResponse;
    if (!result.success) {
      const expired = result["error-codes"]?.includes("timeout-or-duplicate");
      return expired
        ? { success: false, reason: "expired-token", error: "Verification expired. Please try again." }
        : { success: false, reason: "invalid-token", error: "Verification failed. Please try again." };
    }
    if (result.action !== expectedAction) {
      return { success: false, reason: "action-mismatch", error: "Verification failed. Please try again." };
    }
    if (!result.hostname || !expectedHostnames.has(result.hostname.toLowerCase())) {
      return { success: false, reason: "hostname-mismatch", error: "Verification failed. Please try again." };
    }

    return { success: true };
  } catch {
    return { success: false, reason: "siteverify-unavailable", error: "Verification is temporarily unavailable. Please try again." };
  }
};
