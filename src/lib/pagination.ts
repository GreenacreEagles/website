export type PageBounds = {
  defaultLimit: number;
  maxLimit: number;
};

export const PAGE_BOUNDS = {
  news: { defaultLimit: 12, maxLimit: 50 },
  events: { defaultLimit: 20, maxLimit: 100 },
  social: { defaultLimit: 12, maxLimit: 50 },
  socialProfiles: { defaultLimit: 20, maxLimit: 50 },
  teams: { defaultLimit: 50, maxLimit: 100 },
  teamSquad: { defaultLimit: 80, maxLimit: 200 },
  teamStaff: { defaultLimit: 40, maxLimit: 100 },
  teamPosts: { defaultLimit: 30, maxLimit: 100 },
  matchReports: { defaultLimit: 30, maxLimit: 100 },
  users: { defaultLimit: 50, maxLimit: 100 },
  wallets: { defaultLimit: 50, maxLimit: 100 },
  ledger: { defaultLimit: 50, maxLimit: 100 },
  families: { defaultLimit: 25, maxLimit: 100 },
  invitations: { defaultLimit: 25, maxLimit: 100 },
  orders: { defaultLimit: 25, maxLimit: 100 },
  products: { defaultLimit: 50, maxLimit: 200 },
  volunteers: { defaultLimit: 50, maxLimit: 200 },
  eventAdmin: { defaultLimit: 50, maxLimit: 200 },
  wwcc: { defaultLimit: 50, maxLimit: 200 },
  coaching: { defaultLimit: 25, maxLimit: 100 },
  audit: { defaultLimit: 50, maxLimit: 200 },
  notifications: { defaultLimit: 30, maxLimit: 100 },
  sponsors: { defaultLimit: 40, maxLimit: 80 },
  homepage: { defaultLimit: 3, maxLimit: 6 },
  adminSearch: { defaultLimit: 30, maxLimit: 100 },
  pollOptions: { defaultLimit: 2, maxLimit: 20 }
} as const satisfies Record<string, PageBounds>;

export type PageBoundKey = keyof typeof PAGE_BOUNDS;

export const clampLimit = (requested: unknown, bounds: PageBounds): number => {
  const n = typeof requested === "number" ? requested : Number(requested);
  if (!Number.isFinite(n) || n <= 0) return bounds.defaultLimit;
  return Math.min(Math.floor(n), bounds.maxLimit);
};

export const clampOffset = (requested: unknown, maxOffset = 10_000): number => {
  const n = typeof requested === "number" ? requested : Number(requested);
  if (!Number.isFinite(n) || n < 0) return 0;
  return Math.min(Math.floor(n), maxOffset);
};

export const clampSearch = (value: unknown, maxLength = 80): string | null => {
  if (typeof value !== "string") return null;
  const trimmed = value.trim().slice(0, maxLength);
  return trimmed.length > 0 ? trimmed : null;
};

export type CursorPage<T> = {
  items: T[];
  nextCursor: string | null;
  limit: number;
};

export const encodeCursor = (createdAt: string, id: string) => {
  const json = JSON.stringify({ createdAt, id });
  if (typeof Buffer !== "undefined") return Buffer.from(json, "utf8").toString("base64url");
  return btoa(json).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

export const decodeCursor = (value: unknown): { createdAt: string; id: string } | null => {
  if (typeof value !== "string" || !value) return null;
  try {
    const json =
      typeof Buffer !== "undefined"
        ? Buffer.from(value, "base64url").toString("utf8")
        : atob(value.replace(/-/g, "+").replace(/_/g, "/"));
    const parsed = JSON.parse(json) as { createdAt?: string; id?: string };
    if (!parsed?.createdAt || !parsed?.id) return null;
    return { createdAt: parsed.createdAt, id: parsed.id };
  } catch {
    return null;
  }
};
