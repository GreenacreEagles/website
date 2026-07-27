import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage } from "@lib/forms";
import { deleteR2Object, getPublicMediaBucket, getUploadedFile, sponsorLogoObjectKey, validatePublicImage } from "@lib/media";
import { writeAdminAudit } from "@lib/audit";

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

export const GET: APIRoute = (context) => context.redirect(back, 303);

export const POST: APIRoute = async (context) => {
  const correlationId = crypto.randomUUID();
  const redirect = (type: "success" | "error", message: string) =>
    context.redirect(redirectWithMessage(back, type, message), 303);
  try {
  const session = await requirePermission(context, ["sponsors.manage"]);
  if (!session) return context.redirect("/login/", 303);

  let form: FormData;
  try {
    form = await context.request.formData();
  } catch (cause) {
    console.error("sponsor form parsing failed", { cause, contentType: context.request.headers.get("content-type") });
    return redirect("error", "The submitted sponsor form could not be read. Please try again.");
  }
  const raw = Object.fromEntries(form);
  const parsed = schema.safeParse(raw);
  if (!parsed.success) return redirect("error", parsed.error.issues[0]?.message ?? "Check the sponsor details.");

  const service = session.supabase as any;
  const values = parsed.data;
  const id = values.id ?? crypto.randomUUID();
  const { data: before, error: readError } = await service.from("sponsors").select("*").eq("id", id).maybeSingle();
  if (readError) {
    console.error("sponsor database read failed", { code: readError.code, message: readError.message, table: "sponsors", id });
    return redirect("error", "Sponsor details could not be checked.");
  }

  if (values.mode === "delete") {
    if (!before) return redirect("error", "Sponsor not found.");
    const { error } = await service.from("sponsors").delete().eq("id", id);
    if (!error && before.logo_object_key) await deleteR2Object(getPublicMediaBucket(context), before.logo_object_key, "sponsor logo");
    if (!error) {
      const { error: auditError } = await service.from("audit_logs").insert({ actor_id: session.user.id, action: "sponsor.deleted", entity_type: "sponsor", entity_id: id, before_state: before });
      if (auditError) console.error("sponsor audit insert failed", { code: auditError.code, message: auditError.message, action: "sponsor.deleted", id });
    }
    return redirect(error ? "error" : "success", error ? "Sponsor could not be deleted." : "Sponsor deleted.");
  }

  const file = getUploadedFile(form.get("logo"));
  const removeLogo = form.get("remove_logo") === "on";
  let logoObjectKey = before?.logo_object_key ?? null;
  let uploadedKey: string | null = null;
  const bucket = getPublicMediaBucket(context);
  if (file) {
    if (!bucket) return redirect("error", "Image uploads are not configured. Save the sponsor without a logo.");
    const validation = await validatePublicImage(file, context, { maxBytes: 5_242_880, maxWidth: 1600, maxHeight: 1600 });
    if (!validation.ok) return redirect("error", validation.error);
    uploadedKey = sponsorLogoObjectKey(id, file.type);
    try {
      await bucket.put(uploadedKey, validation.bytes, { httpMetadata: { contentType: file.type, cacheControl: "public, max-age=31536000, immutable" } });
    } catch (cause) {
      console.error("sponsor logo upload failed", { cause, operation: "r2.put", binding: "PUBLIC_MEDIA_BUCKET", id });
      return redirect("error", "The logo could not be uploaded. No sponsor record was created.");
    }
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
    logo_url: removeLogo || uploadedKey ? null : before?.logo_url ?? null,
    updated_by: session.user.id,
    ...(before ? {} : { created_by: session.user.id })
  };
  const query = before ? service.from("sponsors").update(record).eq("id", id) : service.from("sponsors").insert(record);
  const { error } = await query;
  if (error && uploadedKey) await deleteR2Object(bucket, uploadedKey, "sponsor upload rollback");
  if (error) {
    console.error("sponsor database mutation failed", { code: error.code, message: error.message, details: error.details, table: "sponsors", mode: values.mode, id });
    return redirect("error", error.message || "Sponsor could not be saved.");
  }

  if (before?.logo_object_key && before.logo_object_key !== logoObjectKey) await deleteR2Object(bucket, before.logo_object_key, "sponsor old logo");
  const actions = [before ? "sponsor.updated" : "sponsor.created"];
  if (before && before.status !== values.status) actions.push(values.status === "active" ? "sponsor.activated" : "sponsor.deactivated");
  if (before && before.display_priority !== values.display_priority) actions.push("sponsor.order_changed");
  if (uploadedKey) actions.push(before?.logo_object_key ? "sponsor.logo_replaced" : "sponsor.logo_uploaded");
  if (removeLogo && before?.logo_object_key) actions.push("sponsor.logo_removed");
  await writeAdminAudit(context, actions.map((action) => ({
    actor_id: session.user.id,
    action,
    entity_type: "sponsor",
    entity_id: id,
    before_state: before,
    after_state: record
  })));
  return redirect("success", before ? "Sponsor updated." : "Sponsor created.");
  } catch (cause) {
    console.error("unexpected sponsor failure", { cause, correlationId });
    return redirect("error", `An unexpected error occurred. Reference ${correlationId}.`);
  }
};
