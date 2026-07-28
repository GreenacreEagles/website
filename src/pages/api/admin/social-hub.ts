import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage } from "@lib/forms";
import { deleteR2Object, getPublicMediaBucket, getUploadedFile, socialPostImageObjectKey, validatePublicImage, putPublicMediaObject } from "@lib/media";

export const prerender=false;
export const GET:APIRoute=(context)=>context.redirect(back,303);
const back="/admin/highlights/";
const platform=z.enum(["instagram","facebook","tiktok"]);
const bool=z.preprocess((value)=>value==="on"||value==="true",z.boolean());
const nullable=(max:number)=>z.preprocess((value)=>value===""?null:value,z.string().trim().max(max).nullable());
const validHttps=(value:string)=>{try{return new URL(value).protocol==="https:";}catch{return false;}};
const profileSchema=z.object({platform,display_name:z.string().trim().min(2).max(120),username:nullable(120),profile_url:z.string().url().max(500),active:bool,sort_order:z.coerce.number().int().min(0).max(10000)}).refine((value)=>validHttps(value.profile_url),{message:"Profile URL must be a valid HTTPS URL."});
const postSchema=z.object({platform,post_url:z.string().url().max(800),title:nullable(180),caption:nullable(2000),image_alt_text:nullable(240),published_at:z.preprocess((value)=>value===""?null:value,z.string().datetime({local:true}).nullable()),active:bool,featured:bool,sort_order:z.coerce.number().int().min(0).max(10000)}).refine((value)=>validHttps(value.post_url),{message:"Post URL must be a valid HTTPS URL."});

export const POST:APIRoute=async(context)=>{
  const correlationId=crypto.randomUUID();
  const redirect=(type:"success"|"error",message:string)=>context.redirect(redirectWithMessage(back,type,message),303);
  try{
    const session=await requirePermission(context,["social_profiles.manage","social_posts.manage"]);
    if(!session)return context.redirect("/login/",303);
    const contentType=context.request.headers.get("content-type")?.toLowerCase()??"";
    if(!contentType.startsWith("multipart/form-data")&&!contentType.startsWith("application/x-www-form-urlencoded"))return new Response(JSON.stringify({error:"Expected form data."}),{status:415,headers:{"content-type":"application/json","cache-control":"no-store"}});
    let formData:FormData;
    try{formData=await context.request.formData();}catch(cause){console.error("social-hub form parsing failed",{cause,contentType,correlationId});return redirect("error","The submitted form could not be read. Please try again.");}
    const raw=Object.fromEntries(formData);
    if(raw.entity!=="profile"&&raw.entity!=="post")return redirect("error","Choose a valid Social Hub record type.");
    const entity=raw.entity;
    const permission=entity==="profile"?"social_profiles.manage":"social_posts.manage";
    const {data:allowed,error:permissionError}=await(session.supabase as any).rpc("has_any_permission",{required_keys:[permission]});
    if(permissionError||allowed!==true)return context.redirect("/admin/",303);
    const table=entity==="profile"?"social_profiles":"social_posts";
    const intent=raw.intent==="delete"?"delete":"save";
    const idResult=z.string().uuid().safeParse(raw.id);
    const bucket=getPublicMediaBucket(context);

    if(intent==="delete"){
      if(!idResult.success)return redirect("error","Invalid record.");
      let oldKey:string|null=null;
      if(entity==="post"){
        const {data:current,error:readError}=await(session.supabase as any).from(table).select("image_object_key").eq("id",idResult.data).maybeSingle();
        if(readError)return redirect("error","The Social Hub record could not be checked.");
        oldKey=current?.image_object_key??null;
      }
      const {error}=await(session.supabase as any).from(table).delete().eq("id",idResult.data);
      if(error){console.error("social-hub delete failed",{entity,code:error.code,message:error.message,correlationId});return redirect("error",error.message??"The record could not be deleted.");}
      if(oldKey)await deleteR2Object(bucket,oldKey,"social post image");
      return redirect("success",`${entity==="profile"?"Social profile":"Social post"} deleted.`);
    }

    const parsed=(entity==="profile"?profileSchema:postSchema).safeParse(raw);
    if(!parsed.success)return redirect("error",parsed.error.issues[0]?.message??"Check the form.");
    const id=idResult.success?idResult.data:crypto.randomUUID();
    const values:any={...parsed.data,updated_by:session.user.id};
    let oldKey:string|null=null;
    let uploadedKey:string|null=null;
    if(entity==="post"){
      if(idResult.success){
        const {data:current,error:readError}=await(session.supabase as any).from(table).select("image_object_key").eq("id",id).maybeSingle();
        if(readError)return redirect("error","The current Social Hub image could not be checked.");
        oldKey=current?.image_object_key??null;
      }
      values.image_object_key=oldKey;
      const file=getUploadedFile(formData.get("image"));
      const removeImage=formData.get("remove_image")==="on";
      if(file){
        if(!bucket)return redirect("error","Image uploads are not configured. Save the post without an image.");
        const validation=await validatePublicImage(file,context,{maxBytes:8_388_608,maxWidth:2560,maxHeight:2560});
        if(!validation.ok)return redirect("error",validation.error);
        uploadedKey=socialPostImageObjectKey(id,file.type);
        try{await putPublicMediaObject(bucket,uploadedKey,validation.bytes,file.type);}catch(cause){console.error("social-hub image upload failed",{cause,correlationId,binding:"PUBLIC_MEDIA_BUCKET"});return redirect("error","The image could not be uploaded. No Social Hub record was created.");}
        values.image_object_key=uploadedKey;
      }else if(removeImage)values.image_object_key=null;
    }
    const result=idResult.success?await(session.supabase as any).from(table).update(values).eq("id",id):await(session.supabase as any).from(table).insert({...values,id,created_by:session.user.id});
    if(result.error&&uploadedKey)await deleteR2Object(bucket,uploadedKey,"social post upload rollback");
    if(result.error){console.error("social-hub database operation failed",{entity,table,code:result.error.code,message:result.error.message,details:result.error.details,correlationId});const message=result.error.code==="23505"?"That social profile or post URL already exists.":result.error.message;return redirect("error",message??"The Social Hub record could not be saved.");}
    if(oldKey&&oldKey!==values.image_object_key)await deleteR2Object(bucket,oldKey,"social post old image");
    return redirect("success",`${entity==="profile"?"Social profile":"Social post"} saved.`);
  }catch(cause){
    console.error("unexpected social-hub failure",{cause,correlationId});
    return redirect("error",`An unexpected error occurred. Reference ${correlationId}.`);
  }
};
