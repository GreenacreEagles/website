import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "../types/database.types";
import { getPublicMediaUrl } from "./media";

export type PublicEventSummary = {
  id:string; slug:string; name:string; summary:string|null; imageUrl:string|null;
  startsAt:string; endsAt:string|null; venueName:string|null; venueSuburb:string|null;
  minimumPriceCents:number|null; currency:string; isFree:boolean; isSoldOut:boolean;
};
export async function getPublicEvents(client:SupabaseClient<Database>,context:{locals?:any}):Promise<PublicEventSummary[]> {
  const {data,error}=await (client as any).from("club_events")
    .select("id,slug,title,description,image_object_key,image_url,starts_at,ends_at,capacity,venue,club_event_ticket_types(price_cents,currency,capacity,active)")
    .eq("status","active").eq("visibility","public").gt("starts_at",new Date().toISOString()).order("starts_at");
  if(error) throw error;
  return (data??[]).map((event:any)=>{
    const types=(event.club_event_ticket_types??[]).filter((type:any)=>type.active);
    const prices=types.map((type:any)=>type.price_cents);
    return {id:event.id,slug:event.slug,name:event.title,summary:event.description,imageUrl:getPublicMediaUrl(event.image_object_key,context)??event.image_url,
      startsAt:event.starts_at,endsAt:event.ends_at,venueName:event.venue??null,venueSuburb:null,
      minimumPriceCents:prices.length?Math.min(...prices):event.price_cents??null,currency:types[0]?.currency??"AUD",
      isFree:prices.length?prices.every((price:number)=>price===0):(event.price_cents??0)===0,isSoldOut:false};
  });
}
