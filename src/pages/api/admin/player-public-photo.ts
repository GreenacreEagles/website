import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { createSupabaseServiceClient } from "@lib/supabase/server";
import { redirectWithMessage, uuidSchema } from "@lib/forms";
import { getPublicMediaBucket, PLAYER_PHOTO_TYPES, playerPhotoMaxBytes, playerPhotoObjectKey } from "@lib/media";

export const prerender = false;
const schema = z.object({
  player_id: uuidSchema,
  action: z.enum(["save", "remove"]),
  photo_consent: z.preprocess((value) => value === "on" || value === "true", z.boolean())
});

const redirect = (context: Parameters<APIRoute>[0], type: "error" | "success", message: string) =>
  context.redirect(redirectWithMessage("/admin/players/", type, message));

export const POST: APIRoute = async (context) => {
  const session = await requirePermission(context, ["players.manage"]);
  if (!session) return context.redirect("/admin/");
  const formData = await context.request.formData();
  const parsed = schema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return redirect(context, "error", "Check the public photo settings.");

  const service = createSupabaseServiceClient(context);
  const { data: current, error: readError } = await (service as any).from("player_records")
    .select("id,photo_object_key,photo_consent,photo_updated_at").eq("id", parsed.data.player_id).maybeSingle();
  if (readError || !current) return redirect(context, "error", "Player record not found.");

  const file = formData.get("photo");
  const hasUpload = file instanceof File && file.size > 0;
  const bucket = getPublicMediaBucket(context);
  let nextKey: string | null = current.photo_object_key;
  let uploadedKey: string | null = null;

  if (hasUpload) {
    if (!bucket) return redirect(context, "error", "Public media storage is not configured. Connect the PUBLIC_MEDIA_BUCKET R2 binding before uploading.");
    if (!PLAYER_PHOTO_TYPES.has(file.type)) return redirect(context, "error", "Use a JPEG, PNG, WebP or AVIF image.");
    if (file.size > playerPhotoMaxBytes(context)) return redirect(context, "error", "The image is larger than the configured upload limit.");
    uploadedKey = playerPhotoObjectKey(current.id, file.type);
    try {
      await bucket.put(uploadedKey, await file.arrayBuffer(), { httpMetadata: { contentType: file.type, cacheControl: "public, max-age=86400" } });
      nextKey = uploadedKey;
    } catch {
      return redirect(context, "error", "The photo could not be uploaded to public media storage.");
    }
  } else if (parsed.data.action === "remove") {
    if (current.photo_object_key && !bucket) return redirect(context, "error", "Public media storage is not configured, so the existing photo cannot be removed safely.");
    nextKey = null;
  }

  const after = { photo_object_key: nextKey, photo_consent: parsed.data.action === "remove" ? false : parsed.data.photo_consent, photo_updated_at: nextKey ? new Date().toISOString() : null };
  const { error: updateError } = await (service as any).from("player_records").update(after).eq("id", current.id);
  if (updateError) {
    if (uploadedKey && bucket) await bucket.delete(uploadedKey).catch(() => undefined);
    return redirect(context, "error", "The database could not be updated; the new upload was rolled back.");
  }

  if (bucket && current.photo_object_key && current.photo_object_key !== nextKey) {
    await bucket.delete(current.photo_object_key).catch(() => undefined);
  }
  const action = parsed.data.action === "remove" ? "player_photo.removed" : hasUpload ? (current.photo_object_key ? "player_photo.replaced" : "player_photo.uploaded") : "player_photo.consent_updated";
  await service.from("audit_logs").insert({
    actor_id: session.user.id, action, entity_type: "player_record", entity_id: current.id,
    before_state: current, after_state: after, reason: "Administrator managed public player photo"
  } as any);
  return redirect(context, "success", parsed.data.action === "remove" ? "Public player photo removed." : "Public player photo settings saved.");
};
