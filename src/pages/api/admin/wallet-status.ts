import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";
export const prerender=false;
const schema=z.object({wallet_id:uuidSchema,status:z.enum(["active","frozen"]),reason:z.string().trim().max(500).optional()});
export const POST:APIRoute=async(context)=>{const session=await requirePermission(context,["wallet.adjust"]);if(!session)return context.redirect("/login/",303);const parsed=schema.safeParse(Object.fromEntries(await context.request.formData()));if(!parsed.success)return context.redirect(redirectWithMessage("/admin/wallets/","error",parsed.error.issues[0]?.message??"Check the wallet action."),303);const{error}=await(session.supabase as any).rpc("set_wallet_status",{target_wallet_id:parsed.data.wallet_id,target_status:parsed.data.status,target_reason:parsed.data.reason||null});return context.redirect(redirectWithMessage("/admin/wallets/",error?"error":"success",error?.message??(parsed.data.status==="frozen"?"Wallet blocked.":"Wallet unblocked.")),303);};
