import { z } from "zod";

export const MAX_JSON_BODY_BYTES = 64 * 1024;
export const MAX_RICH_JSON_BODY_BYTES = 1024 * 1024;
export const MAX_WEBHOOK_BODY_BYTES = 256 * 1024;
export const MAX_SEARCH_LENGTH = 80;
export const MAX_ARRAY_LENGTH = 500;
export const MAX_NOTE_LENGTH = 500;
export const MAX_POST_BODY_LENGTH = 4000;
export const MAX_TITLE_LENGTH = 140;
export const MAX_NAME_LENGTH = 120;
export const MAX_TOP_UP_CENTS = 100_000;
export const MAX_QUANTITY = 50;
export const MAX_FILENAME_LENGTH = 180;

export const nameSchema = z
  .string()
  .trim()
  .min(2)
  .max(MAX_NAME_LENGTH)
  .regex(/^[\p{L}\p{M}\d .'-]+$/u, "Use a valid name.");

export const emailSchema = z.string().trim().toLowerCase().email().max(254);

export const phoneSchema = z
  .string()
  .trim()
  .max(24)
  .regex(/^$|^(\+?61|0)[2-478](?:[ -]?\d){8}$/, "Use a valid Australian phone number.");

export const titleSchema = z.string().trim().min(3).max(MAX_TITLE_LENGTH);

export const postBodySchema = z.string().trim().max(MAX_POST_BODY_LENGTH);

export const noteSchema = z.string().trim().max(MAX_NOTE_LENGTH);

export const safeHttpUrlSchema = z
  .string()
  .trim()
  .max(2048)
  .refine((value) => {
    try {
      const url = new URL(value);
      return url.protocol === "https:" || (url.protocol === "http:" && ["localhost", "127.0.0.1"].includes(url.hostname));
    } catch {
      return false;
    }
  }, "Use a valid HTTPS URL.");

export const quantitySchema = z.coerce.number().int().min(1).max(MAX_QUANTITY);

export const priceCentsSchema = z.coerce.number().int().min(0).max(10_000_000);

export const topUpCentsSchema = z.coerce.number().int().min(100).max(MAX_TOP_UP_CENTS);

export const searchSchema = z.string().trim().max(MAX_SEARCH_LENGTH);

export const paginationSchema = z.object({
  limit: z.coerce.number().int().min(1).max(200).optional(),
  offset: z.coerce.number().int().min(0).max(10_000).optional(),
  cursor: z.string().trim().max(512).optional()
});

export const uuidArraySchema = (max = MAX_ARRAY_LENGTH) =>
  z
    .array(z.string().uuid())
    .min(1)
    .max(max)
    .refine((ids) => new Set(ids).size === ids.length, "Duplicate IDs are not allowed.");

export const idempotencyKeySchema = z
  .string()
  .trim()
  .min(8)
  .max(120)
  .regex(/^[a-zA-Z0-9:_.-]+$/, "Invalid idempotency key.");

export const childUsernameSchema = z
  .string()
  .trim()
  .toLowerCase()
  .regex(/^[a-z0-9][a-z0-9._-]{2,40}$/, "Usernames must be 3–41 characters using letters, numbers, dots, underscores or hyphens.");

export const sanitizeFilename = (name: string): string => {
  const base = String(name ?? "")
    .normalize("NFKC")
    .replace(/[/\\?%*:|"<>]/g, "_")
    .replace(/\s+/g, "-")
    .replace(/^\.+/, "")
    .slice(0, MAX_FILENAME_LENGTH);
  return base || "upload.bin";
};

export const assertNoPathTraversal = (value: string) => {
  if (value.includes("..") || value.includes("\\") || value.startsWith("/")) {
    throw new Error("Invalid file path.");
  }
  return value;
};

export const safeInternalPathSchema = z
  .string()
  .trim()
  .refine((value) => value.startsWith("/") && !value.startsWith("//") && !value.includes("\\"), "Invalid redirect path.");

const contentLength = (request: Request) => {
  const raw = request.headers.get("content-length");
  if (!raw) return null;
  const n = Number(raw);
  return Number.isFinite(n) ? n : null;
};

export const enforceBodyByteLimit = (request: Request, maxBytes = MAX_JSON_BODY_BYTES) => {
  const length = contentLength(request);
  if (length !== null && length > maxBytes) {
    return new Response(JSON.stringify({ error: "Request body is too large." }), {
      status: 413,
      headers: { "content-type": "application/json", "cache-control": "private, no-store" }
    });
  }
  return null;
};

export const readJsonWithLimit = async <T>(request: Request, maxBytes = MAX_JSON_BODY_BYTES): Promise<{ ok: true; data: T } | { ok: false; response: Response }> => {
  const tooLarge = enforceBodyByteLimit(request, maxBytes);
  if (tooLarge) return { ok: false, response: tooLarge };
  try {
    const text = await request.text();
    if (text.length > maxBytes) {
      return {
        ok: false,
        response: new Response(JSON.stringify({ error: "Request body is too large." }), {
          status: 413,
          headers: { "content-type": "application/json", "cache-control": "private, no-store" }
        })
      };
    }
    return { ok: true, data: (text ? JSON.parse(text) : null) as T };
  } catch {
    return {
      ok: false,
      response: new Response(JSON.stringify({ error: "Invalid JSON body." }), {
        status: 400,
        headers: { "content-type": "application/json", "cache-control": "private, no-store" }
      })
    };
  }
};

const PROTECTED_PROFILE_FIELDS = new Set([
  "id",
  "account_status",
  "is_super_admin",
  "role",
  "roles",
  "permissions",
  "wallet_balance_cents",
  "created_at"
]);

export const stripProtectedFields = <T extends Record<string, unknown>>(input: T, extra: string[] = []): Partial<T> => {
  const blocked = new Set([...PROTECTED_PROFILE_FIELDS, ...extra]);
  const out: Partial<T> = {};
  for (const [key, value] of Object.entries(input)) {
    if (!blocked.has(key)) (out as Record<string, unknown>)[key] = value;
  }
  return out;
};
