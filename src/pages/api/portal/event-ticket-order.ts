import type {APIRoute} from "astro";
import {z} from "zod";
import {requireUser} from "@lib/auth/guards";
import {redirectWithMessage} from "@lib/forms";
import {getRuntimeEnv} from "@lib/media";
export const prerender=false;
const schema=z.object({ticket_type_id:z.string().uuid(),quantity:z.coerce.number().int().min(1).max(50),event_slug:z.string().regex(/^[a-z0-9-]+$/)});
export const POST:APIRoute=async context=>{
 const session=await requireUser(context); if(!session)return context.redirect("/login/");
 const parsed=schema.safeParse(Object.fromEntries(await context.request.formData()));
 const back=parsed.success?`/portal/events/${parsed.data.event_slug}/`:"/portal/events/";
 if(!parsed.success)return context.redirect(redirectWithMessage(back,"error","Check the ticket quantity."));
 const provider=String(getRuntimeEnv(context,"PAYMENT_PROVIDER")??"manual");
 const {data,error}=await (session.supabase as any).rpc("create_event_ticket_order",{ticket_type:parsed.data.ticket_type_id,ticket_quantity:parsed.data.quantity,request_key:`event:${session.user.id}:${crypto.randomUUID()}`,payment_provider:provider}).single();
 if(error)return context.redirect(redirectWithMessage(back,"error",error.message.includes("limit")?"Your ticket limit has been reached.":error.message.includes("remain")?"Not enough tickets remain.":"Tickets could not be reserved."));
 if(data.total_cents===0)return context.redirect(redirectWithMessage("/portal/vouchers/","success","Your event tickets are ready in your wallet."));
 return context.redirect(redirectWithMessage(back,"error",provider==="manual"?"Online event payments are not configured yet. Your pending reservation will expire automatically.":"Continue using the configured payment provider."));
};
