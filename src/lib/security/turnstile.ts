type RuntimeContext = {
  request: Request;
};

type TurnstileResult = {
  success: boolean;
  error?: string;
};

const readSecret = () => import.meta.env.TURNSTILE_SECRET_KEY;

const visitorIp = (request: Request) =>
  request.headers.get("CF-Connecting-IP") ?? request.headers.get("X-Forwarded-For")?.split(",")[0]?.trim() ?? undefined;

export const isTurnstileEnabled = () => Boolean(readSecret());

export const verifyTurnstile = async (context: RuntimeContext, formData: FormData, expectedAction: string): Promise<TurnstileResult> => {
  const secret = readSecret();
  if (!secret) return { success: true };

  const token = formData.get("cf-turnstile-response");
  if (typeof token !== "string" || token.length === 0 || token.length > 2048) {
    return { success: false, error: "Verification failed. Please try again." };
  }

  const body = new FormData();
  body.append("secret", secret);
  body.append("response", token);

  const ip = visitorIp(context.request);
  if (ip) body.append("remoteip", ip);

  try {
    const response = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
      method: "POST",
      body
    });
    const result = (await response.json()) as { success?: boolean; action?: string };

    if (!result.success || result.action !== expectedAction) {
      return { success: false, error: "Verification failed. Please try again." };
    }

    return { success: true };
  } catch {
    return { success: false, error: "Verification is temporarily unavailable. Please try again." };
  }
};
