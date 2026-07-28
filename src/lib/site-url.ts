import { env } from "cloudflare:workers";

type SiteContext = { url: URL; request: Request };

const runtimeSiteUrl = () => {
  try {
    return (env as Record<string, unknown>).SITE_URL;
  } catch {
    return undefined;
  }
};

const safeOrigin = (value: unknown) => {
  try {
    const url = new URL(String(value ?? ""));
    const localHttp = url.protocol === "http:" && ["localhost", "127.0.0.1"].includes(url.hostname);
    return url.protocol === "https:" || localHttp ? url.origin : null;
  } catch {
    return null;
  }
};

export const getConfiguredSiteOrigin = (context: SiteContext) =>
  safeOrigin(runtimeSiteUrl()) ?? safeOrigin(import.meta.env.SITE_URL) ?? context.url.origin;