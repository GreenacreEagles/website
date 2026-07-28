import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage } from "@lib/forms";
import { createSupabaseServiceClient } from "@lib/supabase/server";
import { writeAdminAudit } from "@lib/audit";
import { articleImageObjectKey, coachingAttachmentObjectKey, deleteR2Object, getManagedPublicObjectKey, getPrivateMediaBucket, getPublicMediaBucket, getPublicMediaUrl, getRuntimeEnv, getUploadedFile, validatePrivateFile, validatePublicImage, putPublicMediaObject } from "@lib/media";

export const prerender=false;
const nullable=(max:number)=>z.preprocess((value)=>value===""?null:value,z.string().trim().max(max).nullable());
const optionalDate=z.preprocess((value)=>value===""?null:value,z.string().datetime({local:true}).nullable());
const optionalInteger=z.preprocess((value)=>value===""?null:Number(value),z.number().int().min(0).nullable());
const splitList=(value:string|null)=>(value??"").split(",").map((item)=>item.trim()).filter(Boolean);
const slugify=(value:string)=>value.toLowerCase().trim().replace(/[^a-z0-9]+/g,"-").replace(/^-+|-+$/g,"").slice(0,140);
const articleSchema=z.object({title:z.string().trim().min(2).max(180),slug:nullable(140),summary:nullable(500),body:z.string().trim().min(2).max(6000),category:nullable(80),workflow_status:z.enum(["active","inactive"]),publish_at:optionalDate,tags:nullable(240)});
const resourceSchema=z.object({title:z.string().trim().min(2).max(180),slug:nullable(140),resource_type:z.enum(["drill","session_plan","program","policy","video","document","external_link"]),visibility:z.enum(["coaches","team_staff","admins","public"]),summary:nullable(800),body:z.string().trim().max(6000),external_url:nullable(400),duration_minutes:optionalInteger,status:z.enum(["active","inactive"]),age_group_tags:nullable(240),skill_level_tags:nullable(240),equipment_required:nullable(240),review_due_on:z.preprocess((value)=>value===""?null:value,z.string().date().nullable())});

type StoredFile={id:string;bucket:string;object_path:string;mime_type:string|null};
const relatedFile=(row:any):StoredFile|null=>Array.isArray(row?.file_records)?row.file_records[0]??null:row?.file_records??null;

export const POST:APIRoute=async(context)=>{
  const correlationId=crypto.randomUUID();
  let destination="/admin/news/";
  const redirect=(type:"success"|"error",message:string)=>context.redirect(redirectWithMessage(destination,type,message),303);
  try{
    const session=await requirePermission(context,["content.manage","coaching_resources.manage"]);
    if(!session)return context.redirect("/login/",303);
    let formData:FormData;
    try{formData=await context.request.formData();}catch(cause){console.error("content form parsing failed",{cause,correlationId});return redirect("error","The submitted form could not be read.");}
    const raw=Object.fromEntries(formData);
    const entity=raw.entity==="coaching_resource"?"coaching_resource":"article";
    destination=entity==="article"?"/admin/news/":"/admin/coaching-resources/";
    const permission=entity==="article"?"content.manage":"coaching_resources.manage";
    const {data:allowed,error:permissionError}=await(session.supabase as any).rpc("has_any_permission",{required_keys:[permission]});
    if(permissionError||allowed!==true)return context.redirect("/admin/",303);
    const table=entity==="article"?"content_articles":"coaching_resources";
    const idResult=z.string().uuid().safeParse(raw.id);
    const id=idResult.success?idResult.data:crypto.randomUUID();
    const service=session.supabase as any;
    let adminService:any=null;
    const getAdminService=()=>adminService??=(createSupabaseServiceClient(context) as any);
    let current:any=null;
    if(idResult.success){
      const {data,error}=await service.from(table).select("*").eq("id",id).maybeSingle();
      if(error){console.error("content current-record read failed",{entity,code:error.code,message:error.message,correlationId});return redirect("error","The existing record could not be checked.");}
      current=data;
      if(entity==="coaching_resource"&&current?.attachment_file_id){
        const {data:file,error:fileError}=await getAdminService().from("file_records").select("id,bucket,object_path,mime_type").eq("id",current.attachment_file_id).maybeSingle();
        if(fileError){console.error("coaching attachment metadata read failed",{code:fileError.code,message:fileError.message,correlationId});return redirect("error","The existing attachment could not be checked.");}
        current.file_records=file;
      }
    }

    if(raw.intent==="delete"){
      if(!idResult.success||!current)return redirect("error","Invalid record.");
      const oldPublicKey=entity==="article"?getManagedPublicObjectKey(current.featured_image_url,context):null;
      const oldPrivate=entity==="coaching_resource"?relatedFile(current):null;
      const {error}=await service.from(table).delete().eq("id",id);
      if(error)return redirect("error",error.message??"The record could not be deleted.");
      if(oldPublicKey)await deleteR2Object(getPublicMediaBucket(context),oldPublicKey,"article image");
      if(oldPrivate){await deleteR2Object(getPrivateMediaBucket(context),oldPrivate.object_path,"coaching attachment");await getAdminService().from("file_records").delete().eq("id",oldPrivate.id);}
      await writeAdminAudit(context,{actor_id:session.user.id,action:entity==="article"?"content_article.deleted":"coaching_resource.deleted",entity_type:table,entity_id:id,before_state:current,correlation_id:correlationId});
      return redirect("success",entity==="article"?"News article deleted.":"Coaching resource deleted.");
    }

    const parsed=(entity==="article"?articleSchema:resourceSchema).safeParse(raw);
    if(!parsed.success)return redirect("error",parsed.error.issues[0]?.message??"Check the form.");
    let uploadedPublicKey:string|null=null;
    let uploadedPrivate:StoredFile|null=null;
    let oldPublicKey:string|null=null;
    let oldPrivate:StoredFile|null=null;
    let values:any;

    if(entity==="article"){
      const data=parsed.data as z.infer<typeof articleSchema>;
      const currentUrl=current?.featured_image_url??null;
      oldPublicKey=getManagedPublicObjectKey(currentUrl,context);
      let featuredImageUrl=currentUrl;
      const image=getUploadedFile(formData.get("image"));
      if(image){
        const bucket=getPublicMediaBucket(context);
        if(!bucket||!getPublicMediaUrl("configuration-check/image.jpg",context))return redirect("error","Public image storage or delivery is not configured. Save the article without replacing its image.");
        const validation=await validatePublicImage(image,context,{maxBytes:8_388_608,maxWidth:2560,maxHeight:2560});
        if(!validation.ok)return redirect("error",validation.error);
        uploadedPublicKey=articleImageObjectKey(id,image.type);
        try{await putPublicMediaObject(bucket,uploadedPublicKey,validation.bytes,image.type);}catch(cause){console.error("article image upload failed",{cause,correlationId});return redirect("error","The article image could not be uploaded.");}
        featuredImageUrl=getPublicMediaUrl(uploadedPublicKey,context);
      }else if(formData.get("remove_image")==="on")featuredImageUrl=null;
      values={id,title:data.title,slug:data.slug||slugify(data.title),summary:data.summary,body:{type:"plain_text",text:data.body},category:data.category,workflow_status:data.workflow_status,publish_at:data.publish_at,featured_image_url:featuredImageUrl,tags:splitList(data.tags),author_id:session.user.id};
    }else{
      const data=parsed.data as z.infer<typeof resourceSchema>;
      oldPrivate=relatedFile(current);
      let attachmentFileId=current?.attachment_file_id??null;
      const attachment=getUploadedFile(formData.get("attachment"));
      if(attachment){
        const bucket=getPrivateMediaBucket(context);
        if(!bucket)return redirect("error","Private media storage is not configured. Save the resource without an attachment.");
        const validation=await validatePrivateFile(attachment,context);
        if(!validation.ok)return redirect("error",validation.error);
        const objectPath=coachingAttachmentObjectKey(id,attachment.type);
        try{await bucket.put(objectPath,validation.bytes,{httpMetadata:{contentType:attachment.type}});}catch(cause){console.error("coaching attachment upload failed",{cause,correlationId});return redirect("error","The coaching attachment could not be uploaded.");}
        const fileId=crypto.randomUUID();
        const bucketName=String(getRuntimeEnv(context,"R2_PRIVATE_BUCKET_NAME")??"greenacre-eagles-private-media");
        const {error:fileError}=await getAdminService().from("file_records").insert({id:fileId,bucket:bucketName,object_path:objectPath,owner_id:session.user.id,related_entity_type:"coaching_resource",related_entity_id:id,visibility:"role_restricted",mime_type:attachment.type,size_bytes:attachment.size});
        if(fileError){await deleteR2Object(bucket,objectPath,"coaching attachment rollback");console.error("coaching file record insert failed",{code:fileError.code,message:fileError.message,correlationId});return redirect("error","The attachment metadata could not be saved.");}
        uploadedPrivate={id:fileId,bucket:bucketName,object_path:objectPath,mime_type:attachment.type};
        attachmentFileId=fileId;
      }else if(formData.get("remove_attachment")==="on")attachmentFileId=null;
      values={id,title:data.title,slug:data.slug||slugify(data.title),resource_type:data.resource_type,visibility:data.visibility,summary:data.summary,body:{type:"plain_text",text:data.body},external_url:data.external_url,duration_minutes:data.duration_minutes,status:data.status,age_group_tags:splitList(data.age_group_tags),skill_level_tags:splitList(data.skill_level_tags),equipment_required:splitList(data.equipment_required),review_due_on:data.review_due_on,attachment_file_id:attachmentFileId,created_by:current?.created_by??session.user.id};
    }

    const result=idResult.success?await service.from(table).update(values).eq("id",id):await service.from(table).insert(values);
    if(result.error){
      if(uploadedPublicKey)await deleteR2Object(getPublicMediaBucket(context),uploadedPublicKey,"article upload rollback");
      if(uploadedPrivate){await deleteR2Object(getPrivateMediaBucket(context),uploadedPrivate.object_path,"coaching upload rollback");await getAdminService().from("file_records").delete().eq("id",uploadedPrivate.id);}
      console.error("content database mutation failed",{entity,code:result.error.code,message:result.error.message,correlationId});
      return redirect("error",result.error.code==="23505"?"That slug is already in use.":result.error.message??"The record could not be saved.");
    }
    if(oldPublicKey&&oldPublicKey!==uploadedPublicKey&&values.featured_image_url!==current?.featured_image_url)await deleteR2Object(getPublicMediaBucket(context),oldPublicKey,"old article image");
    if(oldPrivate&&oldPrivate.id!==values.attachment_file_id){await deleteR2Object(getPrivateMediaBucket(context),oldPrivate.object_path,"old coaching attachment");await getAdminService().from("file_records").delete().eq("id",oldPrivate.id);}
    await writeAdminAudit(context,{actor_id:session.user.id,action:`${entity}.${idResult.success?"updated":"created"}`,entity_type:table,entity_id:id,before_state:current,after_state:values,correlation_id:correlationId});
    return redirect("success",entity==="article"?"News article saved.":"Coaching resource saved.");
  }catch(cause){
    console.error("unexpected content entry failure",{cause,correlationId});
    return redirect("error",`An unexpected error occurred. Reference ${correlationId}.`);
  }
};
