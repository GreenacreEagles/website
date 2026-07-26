import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage } from "@lib/forms";
import { getPublicMediaBucket, socialPostImageObjectKey, validatePublicImage } from "@lib/media";

export const prerender = false;
const platform = z.enum(["instagram", "facebook", "tiktok"]);
const bool = z.preprocess((v) => v === "on" || v === "true", z.boolean());
const nullable = (max: number) => z.preprocess((v) => v === "" ? null : v, z.string().trim().max(max).nullable());
const httpsFor = (selected: string, value: string) => {
  try {
    const url = new URL(value);
    const domains: Record<string,string> = { instagram:"instagram.com", facebook:"facebook.com", tiktok:"tiktok.com" };
    return url.protocol === "https:" && (url.hostname === domains[selected] || url.hostname.endsWith(`.${domains[selected]}`));
  } catch { return false; }
};
const profileSchema = z.object({ platform, display_name:z.string().trim().min(2).max(120), username:nullable(120), profile_url:z.string().url().max(500), active:bool, sort_order:z.coerce.number().int().min(0).max(10000) })
  .refine((v) => httpsFor(v.platform, v.profile_url), { message:"Profile URL must be an HTTPS URL for the selected platform." });
const postSchema = z.object({ platform, post_url:z.string().url().max(800), title:nullable(180), caption:nullable(2000), image_alt_text:nullable(240), published_at:z.preprocess(v=>v===""?null:v,z.string().nullable()), active:bool, featured:bool, sort_order:z.coerce.number().int().min(0).max(10000) })
  .refine((v) => httpsFor(v.platform, v.post_url), { message:"Post URL must be an HTTPS URL for the selected platform." });

export const POST: APIRoute = async (context) => {
  const formData = await context.request.formData();
  const raw = Object.fromEntries(formData);
  const entity = raw.entity === "profile" ? "profile" : "post";
  const permission = entity === "profile" ? "social_profiles.manage" : "social_posts.manage";
  const session = await requirePermission(context, [permission]);
  if (!session) return context.redirect("/admin/");
  const table = entity === "profile" ? "social_profiles" : "social_posts";
  const intent = raw.intent === "delete" ? "delete" : "save";
  let error: any = null;
  if (intent === "delete") {
    if (!z.string().uuid().safeParse(raw.id).success) return context.redirect(redirectWithMessage("/admin/highlights/","error","Invalid record."));
    ({ error } = await (session.supabase as any).from(table).delete().eq("id",raw.id));
  } else {
    const parsed = (entity === "profile" ? profileSchema : postSchema).safeParse(raw);
    if (!parsed.success) return context.redirect(redirectWithMessage("/admin/highlights/","error",parsed.error.issues[0]?.message ?? "Check the form."));
    const id = typeof raw.id === "string" && z.string().uuid().safeParse(raw.id).success ? raw.id : crypto.randomUUID();
    const values: any = { ...parsed.data, updated_by:session.user.id };
    let oldKey: string | null = null;
    let uploadedKey: string | null = null;
    const file = formData.get("image");
    const removeImage = raw.remove_image === "on";
    const bucket = getPublicMediaBucket(context);
    if (entity === "post") {
      if (typeof raw.id === "string") {
        const { data: current } = await (session.supabase as any).from(table).select("image_object_key").eq("id",id).maybeSingle();
        oldKey = current?.image_object_key ?? null;
      }
      values.image_object_key = oldKey;
      if (file instanceof File && file.size > 0) {
        if (!bucket) return context.redirect(redirectWithMessage("/admin/highlights/","error","Public media storage is not configured; save without an image or connect the R2 binding."));
        const validation = await validatePublicImage(file, context);
        if (!validation.ok) return context.redirect(redirectWithMessage("/admin/highlights/","error",validation.error));
        uploadedKey = socialPostImageObjectKey(id,file.type);
        await bucket.put(uploadedKey,validation.bytes,{httpMetadata:{contentType:file.type,cacheControl:"public, max-age=31536000, immutable"}});
        values.image_object_key = uploadedKey;
      } else if (removeImage) values.image_object_key = null;
    }
    if (typeof raw.id === "string" && z.string().uuid().safeParse(raw.id).success) ({ error } = await (session.supabase as any).from(table).update(values).eq("id",id));
    else ({ error } = await (session.supabase as any).from(table).insert({ ...values, id, created_by:session.user.id }));
    if (error && uploadedKey && bucket) await bucket.delete(uploadedKey).catch(()=>undefined);
    if (!error && bucket && oldKey && oldKey !== values.image_object_key) await bucket.delete(oldKey).catch(()=>undefined);
  }
  const message = error?.code === "23505" ? "That profile or post URL already exists." : error?.message;
  return context.redirect(redirectWithMessage("/admin/highlights/", error ? "error" : "success", message ?? `${entity === "profile" ? "Social profile" : "Social post"} saved.`));
};
