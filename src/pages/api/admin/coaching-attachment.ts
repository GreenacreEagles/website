import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { createSupabaseServiceClient } from "@lib/supabase/server";
import { getPrivateMediaBucket, sanitizeFilename } from "@lib/media";

export const prerender=false;
export const GET:APIRoute=async(context)=>{
  const correlationId=crypto.randomUUID();
  try{
    const session=await requirePermission(context,["coaching_resources.read","coaching_resources.manage"]);
    if(!session)return new Response("Unauthorised",{status:401,headers:{"cache-control":"no-store"}});
    const id=z.string().uuid().safeParse(new URL(context.request.url).searchParams.get("id"));
    if(!id.success)return new Response("Invalid resource",{status:400,headers:{"cache-control":"no-store"}});
    const {data:resource,error}=await(session.supabase as any).from("coaching_resources").select("id,title,slug,attachment_file_id").eq("id",id.data).maybeSingle();
    if(error||!resource?.attachment_file_id)return new Response("Attachment not found",{status:404,headers:{"cache-control":"no-store"}});
    const adminService=createSupabaseServiceClient(context) as any;
    const {data:file,error:fileError}=await adminService.from("file_records").select("object_path,mime_type").eq("id",resource.attachment_file_id).eq("related_entity_type","coaching_resource").eq("related_entity_id",resource.id).maybeSingle();
    if(fileError||!file)return new Response("Attachment not found",{status:404,headers:{"cache-control":"no-store"}});
    const bucket=getPrivateMediaBucket(context);
    if(!bucket?.get)return new Response("Private media storage is unavailable",{status:503,headers:{"cache-control":"no-store"}});
    const object=await bucket.get(file.object_path);
    if(!object)return new Response("Attachment not found",{status:404,headers:{"cache-control":"no-store"}});
    const headers=new Headers({"cache-control":"private, no-store","content-type":file.mime_type??object.httpMetadata?.contentType??"application/octet-stream","x-content-type-options":"nosniff"});
    const extension=String(file.object_path).split(".").pop()?.replace(/[^a-z0-9]/gi,"")||"bin";
    const filename=sanitizeFilename(`${resource.slug||"coaching-resource"}.${extension}`).replace(/[^a-zA-Z0-9._-]/g,"-");
    headers.set("content-disposition",`attachment; filename="${filename}"`);
    object.writeHttpMetadata?.(headers);
    headers.set("content-type",file.mime_type??headers.get("content-type")??"application/octet-stream");
    return new Response(object.body,{status:200,headers});
  }catch(cause){
    console.error("coaching attachment download failed",{cause,correlationId});
    return new Response(`Attachment unavailable. Reference ${correlationId}.`,{status:500,headers:{"cache-control":"no-store"}});
  }
};
