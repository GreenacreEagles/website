import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";
import { deleteR2Object, getPrivateMediaBucket, getRuntimeEnv, getUploadedFile, validatePrivateFile, wwccDocumentObjectKey } from "@lib/media";
import { createSupabaseServiceClient } from "@lib/supabase/server";
export const prerender = false;
const schema = z.object({ assignment_id: uuidSchema, legal_name: z.string().trim().min(2).max(160), date_of_birth: z.string().date(), wwcc_number: z.string().trim().min(5).max(80), expiry_date: z.string().date(), clearance_type: z.enum(["volunteer","paid_worker"]), notes: z.string().trim().max(1000).optional() });
const back="/portal/roles/#wwcc";
export const POST: APIRoute = async (context) => {
  const session=await requireUser(context); if(!session||session.isChildAccount) return context.redirect("/login/",303);
  const form=await context.request.formData(); const parsed=schema.safeParse(Object.fromEntries(form));
  if(!parsed.success) return context.redirect(redirectWithMessage(back,"error",parsed.error.issues[0]?.message??"Check the WWCC details."),303);
  if(parsed.data.expiry_date<new Date().toISOString().slice(0,10)) return context.redirect(redirectWithMessage(back,"error","Enter a current or future WWCC expiry date."),303);
  const {data:assignment}=await (session.supabase as any).from("user_role_assignments").select("id,roles!inner(key)").eq("id",parsed.data.assignment_id).eq("user_id",session.user.id).eq("roles.key","volunteer").is("revoked_at",null).maybeSingle();
  if(!assignment) return context.redirect(redirectWithMessage(back,"error","Start a volunteer request first."),303);
  const submissionId=crypto.randomUUID(); let fileRecordId:string|null=null; let objectPath:string|null=null; const document=getUploadedFile(form.get("document"));
  if(document){ const bucket=getPrivateMediaBucket(context); if(!bucket) return context.redirect(redirectWithMessage(back,"error","Private document storage is unavailable."),303); const validation=await validatePrivateFile(document,context); if(!validation.ok) return context.redirect(redirectWithMessage(back,"error",validation.error),303); fileRecordId=crypto.randomUUID(); objectPath=wwccDocumentObjectKey(session.user.id,submissionId,document.type); await bucket.put(objectPath,validation.bytes,{httpMetadata:{contentType:document.type,cacheControl:"private, no-store"}}); const service=createSupabaseServiceClient(context) as any; const {error:fileError}=await service.from("file_records").insert({id:fileRecordId,bucket:String(getRuntimeEnv(context,"R2_PRIVATE_BUCKET_NAME")??"greenacre-eagles-private-media"),object_path:objectPath,owner_id:session.user.id,related_entity_type:"wwcc_submission",related_entity_id:submissionId,visibility:"private",mime_type:document.type,size_bytes:document.size}); if(fileError){await deleteR2Object(bucket,objectPath,"WWCC rollback"); return context.redirect(redirectWithMessage(back,"error","Supporting file metadata could not be saved."),303);} }
  const {error}=await (session.supabase as any).from("wwcc_submissions").insert({id:submissionId,user_id:session.user.id,role_assignment_id:parsed.data.assignment_id,legal_name:parsed.data.legal_name,date_of_birth:parsed.data.date_of_birth,wwcc_number:parsed.data.wwcc_number.toUpperCase().replace(/\s+/g,""),expiry_date:parsed.data.expiry_date,clearance_type:parsed.data.clearance_type,notes:parsed.data.notes||null,document_file_id:fileRecordId,status:"pending"});
  if(error&&fileRecordId&&objectPath){const service=createSupabaseServiceClient(context) as any; await service.from("file_records").delete().eq("id",fileRecordId); const bucket=getPrivateMediaBucket(context); if(bucket) await deleteR2Object(bucket,objectPath,"WWCC submission rollback");}
  return context.redirect(redirectWithMessage(back,error?"error":"success",error?.message??"WWCC details submitted for external verification."),303);
};
