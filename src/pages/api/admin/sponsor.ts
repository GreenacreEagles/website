import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage } from "@lib/forms";
import { getPublicMediaBucket, sponsorLogoObjectKey, validatePublicImage } from "@lib/media";

export const prerender = false;
const back = "/admin/sponsors/";
const httpsUrl = z.string().trim().url().refine((value) => new URL(value).protocol === "https:", "Website must use HTTPS.");
const schema = z.object({
  id: z.string().uuid().optional(),
  mode: z.enum(["create", "update", "delete"]),
  name: z.string().trim().min(2).max(160),
  description: z.preprocess((v) => v === "" ? null : v, z.string().trim().max(600).nullable()),
  website_url: httpsUrl,
  tier: z.preprocess((v) => v === "" ? null : v, z.string().trim().max(80).nullable()),
  display_priority: z.coerce.number().int().min(0).max(9999),
  status: z.enum(["active", "inactive"])
});

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["sponsors.manage"]);
  if (!session) return context.redirect("/login/");
  const form = await context.request.formData();
  const raw = Object.fromEntries(form);
  const parsed = schema.safeParse(raw);
  if (!parsed.success) return context.redirect(redirectWithMessage(back, "error", parsed.error.issues[0]?.message ?? "Check the sponsor details."));

  const service = session.supabase as any;
  const values = parsed.data;
  const id = values.id ?? crypto.randomUUID();
  const { data: before } = await service.from("sponsors").select("*").eq("id", id).maybeSingle();

  if (values.mode === "delete") {
    if (!before) return context.redirect(redirectWithMessage(back, "error", "Sponsor not found."));
    const { error } = await service.from("sponsors").delete().eq("id", id);
    if (!error && before.logo_object_key) await getPublicMediaBucket(context)?.delete(before.logo_object_key).catch(() => undefined);
    if (!error) await service.from("audit_logs").insert({ actor_id: session.user.id, action: "sponsor.deleted", entity_type: "sponsor", entity_id: id, before_state: before });
    return context.redirect(redirectWithMessage(back, error ? "error" : "success", error ? "Sponsor could not be deleted." : "Sponsor deleted."));
  }

  const file = form.get("logo");
  const removeLogo = form.get("remove_logo") === "on";
  let logoObjectKey = before?.logo_object_key ?? null;
  let uploadedKey: string | null = null;
  const bucket = getPublicMediaBucket(context);
  if (file instanceof File && file.size > 0) {
    if (!bucket) return context.redirect(redirectWithMessage(back, "error", "Public R2 media storage is not configured. You can save the sponsor without a logo."));
    const validation = await validatePublicImage(file, context);
    if (!validation.ok) return context.redirect(redirectWithMessage(back, "error", validation.error));
    uploadedKey = sponsorLogoObjectKey(id, file.type);
    await bucket.put(uploadedKey, validation.bytes, { httpMetadata: { contentType: file.type, cacheControl: "public, max-age=31536000, immutable" } });
    logoObjectKey = uploadedKey;
  } else if (removeLogo) logoObjectKey = null;

  const record = {
    id,
    name: values.name,
    description: values.description,
    website_url: values.website_url,
    tier: values.tier,
    display_priority: values.display_priority,
    status: values.status,
    logo_object_key: logoObjectKey,
    updated_by: session.user.id,
    ...(before ? {} : { created_by: session.user.id })
  };
  const query = before ? service.from("sponsors").update(record).eq("id", id) : service.from("sponsors").insert(record);
  const { error } = await query;
  if (error && uploadedKey) await bucket?.delete(uploadedKey).catch(() => undefined);
  if (error) return context.redirect(redirectWithMessage(back, "error", "Sponsor could not be saved."));

  if (bucket && before?.logo_object_key && before.logo_object_key !== logoObjectKey) await bucket.delete(before.logo_object_key).catch(() => undefined);
  const actions = [before ? "sponsor.updated" : "sponsor.created"];
  if (before && before.status !== values.status) actions.push(values.status === "active" ? "sponsor.activated" : "sponsor.deactivated");
  if (before && before.display_priority !== values.display_priority) actions.push("sponsor.order_changed");
  if (uploadedKey) actions.push(before?.logo_object_key ? "sponsor.logo_replaced" : "sponsor.logo_uploaded");
  if (removeLogo && before?.logo_object_key) actions.push("sponsor.logo_removed");
  if (actions.length > 0) {
    await service.from("audit_logs").insert(actions.map((action) => ({
      actor_id: session.user.id,
      action,
      entity_type: "sponsor",
      entity_id: id,
      before_state: before,
      after_state: record
    })));
  }
  return context.redirect(redirectWithMessage(back, "success", before ? "Sponsor updated." : "Sponsor created."));
};
