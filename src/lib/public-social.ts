import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "../types/database.types";
import { getPublicMediaUrl } from "./media";
export type SocialPlatform = "instagram" | "facebook" | "tiktok";
export type PublicSocialProfile = { id:string; platform:SocialPlatform; displayName:string; username:string|null; profileUrl:string };
export type PublicSocialPost = { id:string; platform:SocialPlatform; title:string|null; caption:string|null; postUrl:string; imageUrl:string|null; imageAltText:string|null; publishedAt:string|null; featured:boolean };
export async function getPublicSocial(client: SupabaseClient<Database>, context:{locals?:any}) {
  const [{data:profiles,error:pe},{data:posts,error:po}] = await Promise.all([
    (client as any).from("social_profiles").select("id,platform,display_name,username,profile_url").eq("active",true).order("sort_order").order("platform"),
    (client as any).from("social_posts").select("id,platform,title,caption,post_url,image_object_key,image_alt_text,published_at,featured").eq("active",true).order("featured",{ascending:false}).order("sort_order").order("published_at",{ascending:false,nullsFirst:false}).order("created_at",{ascending:false})
  ]);
  if(pe||po) throw pe??po;
  return {
    profiles:(profiles??[]).map((r:any)=>({id:r.id,platform:r.platform,displayName:r.display_name,username:r.username,profileUrl:r.profile_url})) as PublicSocialProfile[],
    posts:(posts??[]).map((r:any)=>({id:r.id,platform:r.platform,title:r.title,caption:r.caption,postUrl:r.post_url,imageUrl:getPublicMediaUrl(r.image_object_key,context),imageAltText:r.image_alt_text,publishedAt:r.published_at,featured:r.featured})) as PublicSocialPost[]
  };
}
