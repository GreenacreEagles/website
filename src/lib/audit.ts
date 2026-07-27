import { createSupabaseServiceClient } from "@lib/supabase/server";

type AuditEntry = {
  actor_id: string;
  action: string;
  entity_type: string;
  entity_id?: string | null;
  before_state?: unknown;
  after_state?: unknown;
  reason?: string | null;
  correlation_id?: string | null;
};

export const writeAdminAudit = async (context: any, entries: AuditEntry | AuditEntry[]) => {
  try {
    const service = createSupabaseServiceClient(context) as any;
    const { error } = await service.from("audit_logs").insert(Array.isArray(entries) ? entries : [entries]);
    if (error) {
      console.error("admin audit insert failed", { code:error.code, message:error.message, actions:(Array.isArray(entries)?entries:[entries]).map((entry)=>entry.action) });
      return false;
    }
    return true;
  } catch (cause) {
    console.error("admin audit client failed", { cause, actions:(Array.isArray(entries)?entries:[entries]).map((entry)=>entry.action) });
    return false;
  }
};
