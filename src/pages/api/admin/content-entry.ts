import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage } from "@lib/forms";

export const prerender = false;
const nullable = (max: number) => z.preprocess((value) => value === "" ? null : value, z.string().trim().max(max).nullable());
const optionalDate = z.preprocess((value) => value === "" ? null : value, z.string().nullable());
const optionalInteger = z.preprocess((value) => value === "" ? null : Number(value), z.number().int().min(0).nullable());
const splitList = (value: string | null) => (value ?? "").split(",").map((item) => item.trim()).filter(Boolean);
const slugify = (value: string) => value.toLowerCase().trim().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 140);
const articleSchema = z.object({ title:z.string().trim().min(2).max(180), slug:nullable(140), summary:nullable(500), body:z.string().trim().min(2).max(6000), category:nullable(80), workflow_status:z.enum(["active","inactive"]), publish_at:optionalDate, featured_image_url:nullable(300), tags:nullable(240) });
const resourceSchema = z.object({ title:z.string().trim().min(2).max(180), slug:nullable(140), resource_type:z.enum(["drill","session_plan","program","policy","video","document","external_link"]), visibility:z.enum(["coaches","team_staff","admins","public"]), summary:nullable(800), body:z.string().trim().max(6000), external_url:nullable(400), duration_minutes:optionalInteger, status:z.enum(["active","inactive"]), age_group_tags:nullable(240), skill_level_tags:nullable(240), equipment_required:nullable(240), review_due_on:optionalDate });

export const POST: APIRoute = async (context) => {
  const form = Object.fromEntries(await context.request.formData());
  const entity = form.entity === "coaching_resource" ? "coaching_resource" : "article";
  const redirect = entity === "article" ? "/admin/news/" : "/admin/coaching-resources/";
  const session = await requirePermission(context, [entity === "article" ? "content.manage" : "coaching_resources.manage"]);
  if (!session) return context.redirect("/admin/");
  const id = z.string().uuid().safeParse(form.id);
  if (form.intent === "delete") {
    if (!id.success) return context.redirect(redirectWithMessage(redirect,"error","Invalid record."));
    const table = entity === "article" ? "content_articles" : "coaching_resources";
    const { error } = await session.supabase.from(table).delete().eq("id",id.data);
    return context.redirect(redirectWithMessage(redirect,error?"error":"success",error?.message ?? (entity === "article" ? "News article deleted." : "Coaching resource deleted.")));
  }
  const parsed = (entity === "article" ? articleSchema : resourceSchema).safeParse(form);
  if (!parsed.success) return context.redirect(redirectWithMessage(redirect,"error",parsed.error.issues[0]?.message ?? "Check the form."));
  let result;
  if (entity === "article") {
    const data = parsed.data as z.infer<typeof articleSchema>;
    const values = { title:data.title, slug:data.slug || slugify(data.title), summary:data.summary, body:{type:"plain_text",text:data.body}, category:data.category, workflow_status:data.workflow_status, publish_at:data.publish_at, featured_image_url:data.featured_image_url, tags:splitList(data.tags), author_id:session.user.id };
    result = id.success ? await session.supabase.from("content_articles").update(values).eq("id",id.data) : await session.supabase.from("content_articles").insert(values);
  } else {
    const data = parsed.data as z.infer<typeof resourceSchema>;
    const values = { title:data.title, slug:data.slug || slugify(data.title), resource_type:data.resource_type, visibility:data.visibility, summary:data.summary, body:{type:"plain_text",text:data.body}, external_url:data.external_url, duration_minutes:data.duration_minutes, status:data.status, age_group_tags:splitList(data.age_group_tags), skill_level_tags:splitList(data.skill_level_tags), equipment_required:splitList(data.equipment_required), review_due_on:data.review_due_on, created_by:session.user.id };
    result = id.success ? await (session.supabase as any).from("coaching_resources").update(values).eq("id",id.data) : await (session.supabase as any).from("coaching_resources").insert(values);
  }
  const message = result.error?.code === "23505" ? "That slug is already in use. Choose a different slug." : result.error?.message;
  return context.redirect(redirectWithMessage(redirect,result.error?"error":"success",message ?? (entity === "article" ? "News article saved." : "Coaching resource saved.")));
};
