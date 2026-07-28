import { z } from "zod";

export const uuidSchema = z.string().uuid();
export const optionalUuidSchema = z.preprocess((value) => (value === "" ? null : value), z.string().uuid().nullable().optional());

export const auPhoneSchema = z
  .string()
  .trim()
  .max(24)
  .regex(/^$|^(\+?61|0)[2-478](?:[ -]?\d){8}$/, "Use a valid Australian phone number.");

export const formString = (max = 200) => z.string().trim().max(max);

const authReturnPrefixes = ["/portal/", "/admin/"];

export const safeAuthReturnPath = (value: unknown, fallback = "/portal/") => {
  if (typeof value !== "string" || !value.startsWith("/") || value.startsWith("//") || value.includes("\\")) return fallback;
  try {
    const url = new URL(value, "https://greenacreeagles.local");
    const allowed = authReturnPrefixes.some((prefix) => url.pathname === prefix.slice(0, -1) || url.pathname.startsWith(prefix));
    return allowed ? `${url.pathname}${url.search}` : fallback;
  } catch {
    return fallback;
  }
};

export const redirectWithMessage = (path: string, type: "success" | "error", message: string) => {
  const url = new URL(path, "https://greenacreeagles.local");
  url.searchParams.set(type, message);
  return `${url.pathname}${url.search}`;
};
