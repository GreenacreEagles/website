import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { hasAnyPermission } from "@lib/auth/permissions";
import { getPrivateMediaBucket, sanitizeFilename } from "@lib/media";
import { createSupabaseServiceClient } from "@lib/supabase/server";
import { writeAdminAudit } from "@lib/audit";
import { clientIp, consumeRateLimit, rateLimitKey, rateLimitResponse } from "@lib/security/rate-limit";

export const prerender = false;

export const GET: APIRoute = async (context) => {
  const correlationId = crypto.randomUUID();
  try {
    const session = await requireUser(context);
    if (!session) return new Response("Unauthorised", { status: 401, headers: { "cache-control": "no-store" } });

    const limit = await consumeRateLimit({
      supabase: session.supabase,
      limitClass: "wwcc_document",
      key: rateLimitKey([session.user.id, clientIp(context.request)])
    });
    if (!limit.allowed) return rateLimitResponse(limit);

    const id = z.string().uuid().safeParse(new URL(context.request.url).searchParams.get("id"));
    if (!id.success) return new Response("Invalid submission", { status: 400, headers: { "cache-control": "no-store" } });

    const service = createSupabaseServiceClient(context) as any;
    const { data: submission } = await service
      .from("wwcc_submissions")
      .select("id,user_id,legal_name,document_file_id")
      .eq("id", id.data)
      .maybeSingle();
    if (!submission) return new Response("Document not found", { status: 404, headers: { "cache-control": "no-store" } });

    const canReview = hasAnyPermission(session.permissions, ["wwcc.view", "wwcc.verify"]);
    if (submission.user_id !== session.user.id && !canReview) {
      return new Response("Forbidden", { status: 403, headers: { "cache-control": "no-store" } });
    }

    const { data: file } = await service
      .from("file_records")
      .select("object_path,mime_type")
      .eq("id", submission.document_file_id)
      .eq("owner_id", submission.user_id)
      .eq("visibility", "private")
      .eq("related_entity_type", "wwcc_submission")
      .eq("related_entity_id", submission.id)
      .maybeSingle();
    if (!file) return new Response("Document not found", { status: 404, headers: { "cache-control": "no-store" } });

    const bucket = getPrivateMediaBucket(context);
    if (!bucket) return new Response("Private document storage is unavailable", { status: 503, headers: { "cache-control": "no-store" } });
    const object = await bucket.get(file.object_path);
    if (!object) return new Response("Document not found", { status: 404, headers: { "cache-control": "no-store" } });

    const headers = new Headers({
      "cache-control": "private, no-store",
      "content-type": file.mime_type ?? object.httpMetadata?.contentType ?? "application/octet-stream",
      "content-security-policy": "default-src 'none'; sandbox",
      "x-content-type-options": "nosniff"
    });
    const extension = String(file.object_path).split(".").pop()?.replace(/[^a-z0-9]/gi, "") || "bin";
    const safeName = sanitizeFilename(String(submission.legal_name ?? "wwcc-document")).replace(/[^a-zA-Z0-9._-]/g, "-");
    headers.set("content-disposition", `attachment; filename="${safeName}-WWCC.${extension}"`);
    object.writeHttpMetadata?.(headers);
    headers.set("cache-control", "private, no-store");
    headers.set("content-type", file.mime_type ?? headers.get("content-type") ?? "application/octet-stream");
    if (canReview && submission.user_id !== session.user.id) await writeAdminAudit(context, { actor_id: session.user.id, action: "wwcc.document_viewed", entity_type: "wwcc_submission", entity_id: submission.id, after_state: { document_file_id: submission.document_file_id }, correlation_id: correlationId });
    return new Response(object.body, { status: 200, headers });
  } catch (cause) {
    console.error("WWCC document download failed", { cause, correlationId });
    return new Response(`Document unavailable. Reference ${correlationId}.`, {
      status: 500,
      headers: { "cache-control": "no-store" }
    });
  }
};
