import type{APIRoute}from"astro";
import{z}from"zod";
import{requirePermission}from"@lib/auth/guards";
import{redirectWithMessage}from"@lib/forms";
import{writeAdminAudit}from"@lib/audit";
import {deleteR2Object,getPublicMediaBucket,getUploadedFile,merchandiseImageObjectKey,validatePublicImage, putPublicMediaObject } from "@lib/media";
export const prerender=false;
const back="/admin/merchandise/";
const nullable=(max:number)=>z.preprocess((value)=>value===""?null:value,z.string().trim().max(max).nullable());
const checkbox=z.preprocess((value)=>value==="on"||value==="true",z.boolean());
const optionalDate=z.preprocess((value)=>value===""?null:value,z.string().datetime({local:true}).nullable());
const dollars=z.preprocess((value)=>value===""?null:Math.round(Number(value)*100),z.number().int().min(0).max(10000000).nullable());
const productSchema=z.object({name:z.string().trim().min(2).max(160),description:nullable(800),category:nullable(100),status:z.enum(["active","inactive"]),featured:checkbox,sort_order:z.coerce.number().int().min(0).max(10000),available_from:optionalDate,available_until:optionalDate});
const variantSchema=z.object({product_id:z.string().uuid(),sku:nullable(80),size:nullable(40),colour:nullable(80),price:dollars.refine((value)=>value!==null,"Price is required."),sale_price:dollars,stock_quantity:z.coerce.number().int().min(0).max(999999),low_stock_threshold:z.coerce.number().int().min(0).max(999999),is_active:checkbox});

export const POST:APIRoute=async(context)=>{
 const correlationId=crypto.randomUUID();
 const redirect=(type:"success"|"error",message:string)=>context.redirect(redirectWithMessage(back,type,message),303);
 try{
  const session=await requirePermission(context,["merchandise.manage"]);if(!session)return context.redirect("/login/",303);
  let formData:FormData;try{formData=await context.request.formData();}catch(cause){console.error("merchandise form parsing failed",{cause,correlationId});return redirect("error","The submitted form could not be read.");}
  const raw=Object.fromEntries(formData);const entity=raw.entity==="variant"?"variant":"product";const table=entity==="variant"?"merchandise_variants":"merchandise_products";const idResult=z.string().uuid().safeParse(raw.id);const service=session.supabase as any;const bucket=getPublicMediaBucket(context);
  let current:any=null;if(idResult.success){const selection=entity==="product"?"*":"*";const read=await service.from(table).select(selection).eq("id",idResult.data).maybeSingle();if(read.error)return redirect("error","The existing merchandise record could not be checked.");current=read.data;}
  if(raw.intent==="delete"){
   if(!idResult.success||!current)return redirect("error","Invalid merchandise record.");
   const{error}=await service.from(table).delete().eq("id",idResult.data);if(error)return redirect("error",error.message??"The merchandise record could not be deleted.");
   if(entity==="product"&&current.image_object_key)await deleteR2Object(bucket,current.image_object_key,"merchandise image");
   await writeAdminAudit(context,{actor_id:session.user.id,action:`merchandise_${entity}.deleted`,entity_type:table,entity_id:idResult.data,before_state:current,correlation_id:correlationId});
   return redirect("success",entity==="variant"?"Variant deleted.":"Product deleted.");
  }
  const parsed=(entity==="variant"?variantSchema:productSchema).safeParse(raw);if(!parsed.success)return redirect("error",parsed.error.issues[0]?.message??"Check the merchandise details.");
  const id=idResult.success?idResult.data:crypto.randomUUID();let values:Record<string,unknown>;let uploadedKey:string|null=null;let oldKey:string|null=null;
  if(entity==="variant"){
   const{price,sale_price,...data}=parsed.data as z.infer<typeof variantSchema>;values={...data,price_cents:price,sale_price_cents:sale_price};
  }else{
   const data=parsed.data as z.infer<typeof productSchema>;oldKey=current?.image_object_key??null;let imageObjectKey=oldKey;let imageUrl=current?.image_url??null;const image=getUploadedFile(formData.get("image"));
   if(image){if(!bucket)return redirect("error","Public image storage is unavailable. Save the product without replacing its image.");const validation=await validatePublicImage(image,context,{maxBytes:8_388_608,maxWidth:2560,maxHeight:2560});if(!validation.ok)return redirect("error",validation.error);uploadedKey=merchandiseImageObjectKey(id,image.type);try{await putPublicMediaObject(bucket,uploadedKey,validation.bytes,image.type);}catch(cause){console.error("merchandise image upload failed",{cause,correlationId});return redirect("error","The product image could not be uploaded.");}imageObjectKey=uploadedKey;imageUrl=null;}else if(formData.get("remove_image")==="on"){imageObjectKey=null;imageUrl=null;}
   values={...data,id,image_url:imageUrl,image_object_key:imageObjectKey};
  }
  const result=idResult.success?await service.from(table).update(values).eq("id",id):await service.from(table).insert(values);
  if(result.error&&uploadedKey)await deleteR2Object(bucket,uploadedKey,"merchandise upload rollback");
  if(result.error){console.error("merchandise mutation failed",{entity,code:result.error.code,message:result.error.message,correlationId});return redirect("error",result.error.code==="23505"?"That SKU is already in use.":result.error.message??"The merchandise record could not be saved.");}
  if(entity==="product"&&oldKey&&oldKey!==(values as any).image_object_key)await deleteR2Object(bucket,oldKey,"old merchandise image");
  await writeAdminAudit(context,{actor_id:session.user.id,action:`merchandise_${entity}.${idResult.success?"updated":"created"}`,entity_type:table,entity_id:id,before_state:current,after_state:values,correlation_id:correlationId});
  return redirect("success",entity==="variant"?"Variant saved.":"Product saved.");
 }catch(cause){console.error("unexpected merchandise failure",{cause,correlationId});return redirect("error",`An unexpected error occurred. Reference ${correlationId}.`);}
};
