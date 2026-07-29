import type { SupabaseClient } from "@supabase/supabase-js";
import { logWarn } from "../logging.ts";

export type RateLimitClass =
  | "auth"
  | "posts"
  | "likes"
  | "invitations"
  | "checkout"
  | "wallet"
  | "uploads"
  | "admin_search"
  | "wwcc_document"
  | "contact"
  | "exports"
  | "child_account"
  | "vouchers"
  | "generic";

type LimitConfig = {
  windowSeconds: number;
  maxRequests: number;
};

/** Practical club-scale defaults from the production readiness audit. */
export const RATE_LIMITS: Record<RateLimitClass, LimitConfig> = {
  auth: { windowSeconds: 60, maxRequests: 5 },
  posts: { windowSeconds: 60, maxRequests: 5 },
  likes: { windowSeconds: 60, maxRequests: 20 },
  invitations: { windowSeconds: 3600, maxRequests: 5 },
  checkout: { windowSeconds: 60, maxRequests: 5 },
  wallet: { windowSeconds: 60, maxRequests: 3 },
  uploads: { windowSeconds: 600, maxRequests: 5 },
  admin_search: { windowSeconds: 60, maxRequests: 30 },
  wwcc_document: { windowSeconds: 3600, maxRequests: 20 },
  contact: { windowSeconds: 3600, maxRequests: 10 },
  exports: { windowSeconds: 3600, maxRequests: 10 },
  child_account: { windowSeconds: 3600, maxRequests: 10 },
  vouchers: { windowSeconds: 60, maxRequests: 5 },
  generic: { windowSeconds: 60, maxRequests: 60 }
};

export type RateLimitResult = {
  allowed: boolean;
  remaining: number;
  resetAt: string;
  retryAfterSeconds: number;
};

const memoryBuckets = new Map<string, { count: number; resetAt: number }>();

const memoryConsume = (key: string, config: LimitConfig): RateLimitResult => {
  const now = Date.now();
  const existing = memoryBuckets.get(key);
  if (!existing || existing.resetAt <= now) {
    const resetAt = now + config.windowSeconds * 1000;
    memoryBuckets.set(key, { count: 1, resetAt });
    return { allowed: true, remaining: config.maxRequests - 1, resetAt: new Date(resetAt).toISOString(), retryAfterSeconds: config.windowSeconds };
  }
  existing.count += 1;
  const allowed = existing.count <= config.maxRequests;
  return {
    allowed,
    remaining: Math.max(0, config.maxRequests - existing.count),
    resetAt: new Date(existing.resetAt).toISOString(),
    retryAfterSeconds: Math.max(1, Math.ceil((existing.resetAt - now) / 1000))
  };
};

export const clientIp = (request: Request): string => {
  const cf = request.headers.get("cf-connecting-ip");
  if (cf) return cf.trim();
  const forwarded = request.headers.get("x-forwarded-for");
  if (forwarded) return forwarded.split(",")[0]?.trim() || "unknown";
  return "unknown";
};

export const rateLimitKey = (parts: Array<string | null | undefined>) =>
  parts.filter(Boolean).join(":");

/**
 * Prefer the database RPC when available (shared across isolates).
 * Falls back to in-memory isolate limiting so routes still fail closed under abuse.
 */
export const consumeRateLimit = async (options: {
  supabase?: SupabaseClient<any> | null;
  limitClass: RateLimitClass;
  key: string;
  config?: LimitConfig;
}): Promise<RateLimitResult> => {
  const config = options.config ?? RATE_LIMITS[options.limitClass];
  const bucketKey = `${options.limitClass}:${options.key}`;

  if (options.supabase) {
    try {
      const { data, error } = await (options.supabase as any).rpc("consume_rate_limit", {
        bucket_key: bucketKey,
        window_seconds: config.windowSeconds,
        max_requests: config.maxRequests
      });
      if (!error && data) {
        const row = Array.isArray(data) ? data[0] : data;
        return {
          allowed: Boolean(row.allowed),
          remaining: Number(row.remaining ?? 0),
          resetAt: String(row.reset_at ?? new Date(Date.now() + config.windowSeconds * 1000).toISOString()),
          retryAfterSeconds: Number(row.retry_after_seconds ?? config.windowSeconds)
        };
      }
    } catch {
      // Fall through to memory limiter.
    }
  }

  return memoryConsume(bucketKey, config);
};

export const rateLimitResponse = (result: RateLimitResult, message = "Too many attempts. Please try again later.") => {
  logWarn("rate_limit.blocked", {
    operation: "rate_limit",
    status: 429,
    errorCode: "rate_limited",
    rateLimited: true
  });
  return new Response(JSON.stringify({ error: message, retry_after_seconds: result.retryAfterSeconds }), {
    status: 429,
    headers: {
      "content-type": "application/json",
      "cache-control": "private, no-store",
      "retry-after": String(result.retryAfterSeconds),
      "x-ratelimit-remaining": String(result.remaining),
      "x-ratelimit-reset": result.resetAt
    }
  });
};

export const rateLimitRedirect = (path: string, result: RateLimitResult) => {
  const minutes = Math.max(1, Math.ceil(result.retryAfterSeconds / 60));
  const url = new URL(path, "https://greenacreeagles.local");
  url.searchParams.set("error", `Too many attempts; try again in ${minutes} minute${minutes === 1 ? "" : "s"}.`);
  return `${url.pathname}${url.search}`;
};
