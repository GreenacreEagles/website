import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage } from "@lib/forms";
import {
  deleteR2Object,
  galleryImageObjectKey,
  getPublicMediaBucket,
  getUploadedFile,
  putPublicMediaObject,
  validatePublicImage
} from "@lib/media";

export const prerender = false;
const back = "/admin/gallery/";
const maxPhotos = 12;
const maxBytes = 8_388_608;

const redirect = (context: Parameters<APIRoute>[0], type: "success" | "error", message: string) =>
  context.redirect(redirectWithMessage(back, type, message), 303);

const photoFiles = (form: FormData) =>
  form.getAll("photos").map((value) => getUploadedFile(value)).filter((file) => file !== null);

const uploadPhotos = async (context: Parameters<APIRoute>[0], albumId: string, files: NonNullable<ReturnType<typeof getUploadedFile>>[]) => {
  const bucket = getPublicMediaBucket(context);
  if (!bucket) return { error: "Photo upload is not configured.", keys: [] as string[] };
  const keys: string[] = [];
  for (const file of files) {
    const validation = await validatePublicImage(file, context, { maxBytes, maxWidth: 8000, maxHeight: 8000 });
    if (!validation.ok) {
      await Promise.all(keys.map((key) => deleteR2Object(bucket, key, "gallery upload rollback")));
      return { error: validation.error, keys: [] as string[] };
    }
    const key = galleryImageObjectKey(albumId, file.type);
    try {
      await putPublicMediaObject(bucket, key, validation.bytes, file.type);
    } catch (cause) {
      console.error("gallery image upload failed", { cause, albumId });
      await Promise.all(keys.map((existing) => deleteR2Object(bucket, existing, "gallery upload rollback")));
      return { error: "A photo could not be uploaded. Nothing new was saved.", keys: [] as string[] };
    }
    keys.push(key);
  }
  return { error: null, keys };
};

export const POST: APIRoute = async (context) => {
  const correlationId = crypto.randomUUID();
  try {
    const session = await requirePermission(context, ["content.manage"]);
    if (!session) return context.redirect("/login/", 303);
    const { data: allowed, error: permissionError } = await (session.supabase as any).rpc("has_any_permission", { required_keys: ["content.manage"] });
    if (permissionError || allowed !== true) return context.redirect("/admin/", 303);

    const contentType = context.request.headers.get("content-type")?.toLowerCase() ?? "";
    if (!contentType.startsWith("multipart/form-data") && !contentType.startsWith("application/x-www-form-urlencoded")) {
      return new Response(JSON.stringify({ error: "Expected form data." }), { status: 415, headers: { "content-type": "application/json", "cache-control": "no-store" } });
    }

    let form: FormData;
    try {
      form = await context.request.formData();
    } catch (cause) {
      console.error("gallery form parsing failed", { cause, correlationId });
      return redirect(context, "error", "The form could not be read. Please try again.");
    }

    const db = session.supabase as any;
    const intent = String(form.get("intent") ?? "save");
    const albumId = z.string().uuid().safeParse(form.get("album_id"));
    const photoId = z.string().uuid().safeParse(form.get("photo_id"));

    if (intent === "delete-album") {
      if (!albumId.success) return redirect(context, "error", "That album could not be found.");
      const { data: photos, error: readError } = await db.from("gallery_photos").select("object_key").eq("album_id", albumId.data);
      if (readError) return redirect(context, "error", "The album photos could not be checked.");
      const { error } = await db.from("gallery_albums").delete().eq("id", albumId.data);
      if (error) return redirect(context, "error", "The album could not be deleted.");
      const bucket = getPublicMediaBucket(context);
      await Promise.all((photos ?? []).map((photo: { object_key: string }) => deleteR2Object(bucket, photo.object_key, "gallery album photo")));
      return redirect(context, "success", "Album deleted.");
    }

    if (intent === "delete-photo") {
      if (!photoId.success) return redirect(context, "error", "That photo could not be found.");
      const { data: photo, error: readError } = await db.from("gallery_photos").select("id,object_key").eq("id", photoId.data).maybeSingle();
      if (readError || !photo) return redirect(context, "error", "That photo could not be found.");
      const { error } = await db.from("gallery_photos").delete().eq("id", photo.id);
      if (error) return redirect(context, "error", "The photo could not be removed.");
      await deleteR2Object(getPublicMediaBucket(context), photo.object_key, "gallery photo");
      return redirect(context, "success", "Photo removed.");
    }

    if (intent === "cover") {
      if (!photoId.success) return redirect(context, "error", "That photo could not be found.");
      const { data: photo, error: readError } = await db.from("gallery_photos").select("id,album_id").eq("id", photoId.data).maybeSingle();
      if (readError || !photo) return redirect(context, "error", "That photo could not be found.");
      const { data: photos, error: listError } = await db.from("gallery_photos").select("id,sort_order,created_at").eq("album_id", photo.album_id);
      if (listError) return redirect(context, "error", "The album photos could not be reordered.");
      const ordered = [...(photos ?? [])].sort((a, b) => a.sort_order - b.sort_order || String(a.created_at).localeCompare(String(b.created_at)));
      const next = [photo.id, ...ordered.map((item) => item.id).filter((id) => id !== photo.id)];
      for (const [index, id] of next.entries()) {
        const { error } = await db.from("gallery_photos").update({ sort_order: index }).eq("id", id);
        if (error) return redirect(context, "error", "The cover photo could not be saved.");
      }
      return redirect(context, "success", "Cover photo updated.");
    }

    const title = z.string().trim().min(1).max(120).safeParse(form.get("title"));
    if (!title.success) return redirect(context, "error", "Add a heading of 120 characters or fewer.");
    const published = form.get("published") === "on";
    const files = photoFiles(form);
    if (files.length > maxPhotos) return redirect(context, "error", `Choose ${maxPhotos} photos or fewer.`);

    if (!albumId.success) {
      if (files.length === 0) return redirect(context, "error", "Add at least one photo.");
      const id = crypto.randomUUID();
      const uploaded = await uploadPhotos(context, id, files);
      if (uploaded.error) return redirect(context, "error", uploaded.error);
      const { error: albumError } = await db.from("gallery_albums").insert({
        id,
        title: title.data,
        published,
        created_by: session.user.id,
        updated_by: session.user.id
      });
      if (albumError) {
        const bucket = getPublicMediaBucket(context);
        await Promise.all(uploaded.keys.map((key) => deleteR2Object(bucket, key, "gallery album rollback")));
        return redirect(context, "error", "The album could not be saved.");
      }
      const rows = uploaded.keys.map((object_key, index) => ({ album_id: id, object_key, sort_order: index }));
      const { error: photoError } = await db.from("gallery_photos").insert(rows);
      if (photoError) {
        await db.from("gallery_albums").delete().eq("id", id);
        const bucket = getPublicMediaBucket(context);
        await Promise.all(uploaded.keys.map((key) => deleteR2Object(bucket, key, "gallery album rollback")));
        return redirect(context, "error", "The photos could not be saved.");
      }
      return redirect(context, "success", "Album added to the gallery.");
    }

    const { data: existing, error: existingError } = await db.from("gallery_albums").select("id").eq("id", albumId.data).maybeSingle();
    if (existingError || !existing) return redirect(context, "error", "That album could not be found.");
    const { data: existingPhotos, error: countError } = await db.from("gallery_photos").select("sort_order").eq("album_id", albumId.data);
    if (countError) return redirect(context, "error", "The album photos could not be checked.");
    const currentCount = existingPhotos?.length ?? 0;
    if (currentCount + files.length > maxPhotos) return redirect(context, "error", `An album can have ${maxPhotos} photos.`);
    const nextSort = (existingPhotos ?? []).reduce((max: number, photo: { sort_order: number }) => Math.max(max, photo.sort_order), -1) + 1;
    const uploaded = files.length ? await uploadPhotos(context, albumId.data, files) : { error: null, keys: [] as string[] };
    if (uploaded.error) return redirect(context, "error", uploaded.error);
    const { error: updateError } = await db.from("gallery_albums").update({
      title: title.data,
      published,
      updated_by: session.user.id
    }).eq("id", albumId.data);
    if (updateError) {
      const bucket = getPublicMediaBucket(context);
      await Promise.all(uploaded.keys.map((key) => deleteR2Object(bucket, key, "gallery update rollback")));
      return redirect(context, "error", "The album could not be saved.");
    }
    if (uploaded.keys.length) {
      const rows = uploaded.keys.map((object_key, index) => ({ album_id: albumId.data, object_key, sort_order: nextSort + index }));
      const { error: photoError } = await db.from("gallery_photos").insert(rows);
      if (photoError) {
        const bucket = getPublicMediaBucket(context);
        await Promise.all(uploaded.keys.map((key) => deleteR2Object(bucket, key, "gallery update rollback")));
        return redirect(context, "error", "The new photos could not be saved.");
      }
    }
    return redirect(context, "success", "Album saved.");
  } catch (cause) {
    console.error("unexpected gallery failure", { cause, correlationId });
    return redirect(context, "error", `Something went wrong. Reference ${correlationId}.`);
  }
};
