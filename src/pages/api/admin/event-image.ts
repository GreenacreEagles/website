import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage } from "@lib/forms";
import { eventImageObjectKey, getPublicMediaBucket, getUploadedFile, validatePublicImage } from "@lib/media";

export const prerender = false;
const back = "/admin/events/";

export const POST: APIRoute = async (context) => {
  const redirect = (type: "success" | "error", message: string) =>
    context.redirect(redirectWithMessage(back, type, message), 303);
  const session = await requirePermission(context, ["events.manage"]);
  if (!session) return context.redirect("/login/", 303);

  let form: FormData;
  try {
    form = await context.request.formData();
  } catch (cause) {
    console.error("event image form parsing failed", { cause, contentType: context.request.headers.get("content-type") });
    return redirect("error", "The submitted image form could not be read.");
  }
  const eventId = form.get("event_id");
  if (!z.string().uuid().safeParse(eventId).success) return redirect("error", "Invalid event.");

  const service = session.supabase as any;
  const { data: event, error: readError } = await service.from("club_events").select("image_object_key").eq("id", eventId).maybeSingle();
  if (readError || !event) {
    if (readError) console.error("event image database read failed", { code: readError.code, message: readError.message, eventId });
    return redirect("error", "Event not found.");
  }

  const remove = form.get("action") === "remove";
  const file = getUploadedFile(form.get("image"));
  const bucket = getPublicMediaBucket(context);
  let nextKey: string | null = event.image_object_key;
  let uploadedKey: string | null = null;

  if (remove) {
    if (event.image_object_key && !bucket) return redirect("error", "Public media storage is not configured, so the existing image cannot be removed safely.");
    nextKey = null;
  } else {
    if (!file) return redirect("error", "Choose a supported image within the upload limit.");
    if (!bucket) return redirect("error", "Image uploads are not configured.");
    const validation = await validatePublicImage(file, context);
    if (!validation.ok) return redirect("error", validation.error);
    uploadedKey = eventImageObjectKey(String(eventId), file.type);
    try {
      await bucket.put(uploadedKey, validation.bytes, { httpMetadata: { contentType: file.type, cacheControl: "public, max-age=31536000, immutable" } });
    } catch (cause) {
      console.error("event image upload failed", { cause, operation: "r2.put", binding: "PUBLIC_MEDIA_BUCKET", eventId });
      return redirect("error", "The event image could not be uploaded.");
    }
    nextKey = uploadedKey;
  }

  const { error } = await service.from("club_events").update({ image_object_key: nextKey }).eq("id", eventId);
  if (error && uploadedKey) await bucket?.delete(uploadedKey).catch((cause) => console.error("event image rollback failed", { cause, eventId, uploadedKey }));
  if (error) {
    console.error("event image database update failed", { code: error.code, message: error.message, eventId });
    return redirect("error", "Event image could not be saved.");
  }
  if (bucket && event.image_object_key && event.image_object_key !== nextKey) {
    await bucket.delete(event.image_object_key).catch((cause) => console.error("event old image cleanup failed", { cause, eventId }));
  }
  const { error: auditError } = await service.from("audit_logs").insert({
    actor_id: session.user.id,
    action: remove ? "event.image_removed" : event.image_object_key ? "event.image_replaced" : "event.image_uploaded",
    entity_type: "club_event",
    entity_id: eventId,
    before_state: { image_object_key: event.image_object_key },
    after_state: { image_object_key: nextKey }
  });
  if (auditError) console.error("event image audit insert failed", { code: auditError.code, message: auditError.message, eventId });
  return redirect("success", "Event image updated.");
};
