import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";
import {
  deleteR2Object,
  getPrivateMediaBucket,
  getRuntimeEnv,
  getUploadedFile,
  validatePrivateFile,
  wwccDocumentObjectKey
} from "@lib/media";
import { createSupabaseServiceClient } from "@lib/supabase/server";

export const prerender = false;

const schema = z.object({
  assignment_id: uuidSchema,
  legal_name: z.string().trim().min(2).max(160),
  wwcc_number: z.string().trim().min(5).max(80),
  expiry_date: z.string().date(),
  notes: z.string().trim().max(1000).optional()
});

const back = "/portal/roles/#wwcc";

export const POST: APIRoute = async (context) => {
  const correlationId = crypto.randomUUID();
  const redirect = (type: "success" | "error", message: string) =>
    context.redirect(redirectWithMessage(back, type, message), 303);

  try {
    const session = await requireUser(context);
    if (!session) return context.redirect("/login/", 303);
    if (session.isChildAccount) return redirect("error", "WWCC submissions are not available for child accounts.");

    let form: FormData;
    try {
      form = await context.request.formData();
    } catch (cause) {
      console.error("WWCC form parsing failed", { cause, correlationId });
      return redirect("error", "The submitted WWCC form could not be read.");
    }

    const parsed = schema.safeParse(Object.fromEntries(form));
    if (!parsed.success) return redirect("error", parsed.error.issues[0]?.message ?? "Check the WWCC details.");
    if (parsed.data.expiry_date < new Date().toISOString().slice(0, 10)) {
      return redirect("error", "Enter a current or future WWCC expiry date.");
    }

    const { data: assignment } = await (session.supabase as any)
      .from("user_role_assignments")
      .select("id,status,roles!inner(key)")
      .eq("id", parsed.data.assignment_id)
      .eq("user_id", session.user.id)
      .eq("roles.key", "volunteer")
      .is("revoked_at", null)
      .maybeSingle();
    if (!assignment) return redirect("error", "A club-assigned volunteer role is required.");

    const document = getUploadedFile(form.get("document"));
    if (!document) return redirect("error", "Choose a supporting WWCC document.");

    const bucket = getPrivateMediaBucket(context);
    if (!bucket) return redirect("error", "Private document storage is unavailable.");

    const validation = await validatePrivateFile(document, context);
    if (!validation.ok) return redirect("error", validation.error);

    const submissionId = crypto.randomUUID();
    const fileRecordId = crypto.randomUUID();
    const objectPath = wwccDocumentObjectKey(session.user.id, submissionId, document.type);
    const bucketName = String(getRuntimeEnv(context, "R2_PRIVATE_BUCKET_NAME") ?? "greenacre-eagles-private-media");

    try {
      await bucket.put(objectPath, validation.bytes, {
        httpMetadata: { contentType: document.type, cacheControl: "private, no-store" }
      });
    } catch (cause) {
      console.error("WWCC private document upload failed", { cause, correlationId });
      return redirect("error", "The supporting document could not be uploaded.");
    }

    const service = createSupabaseServiceClient(context) as any;
    const { error: fileError } = await service.from("file_records").insert({
      id: fileRecordId,
      bucket: bucketName,
      object_path: objectPath,
      owner_id: session.user.id,
      related_entity_type: "wwcc_submission",
      related_entity_id: submissionId,
      visibility: "private",
      mime_type: document.type,
      size_bytes: document.size
    });
    if (fileError) {
      await deleteR2Object(bucket, objectPath, "WWCC file record rollback");
      console.error("WWCC file record insert failed", { code: fileError.code, message: fileError.message, correlationId });
      return redirect("error", "The supporting document metadata could not be saved.");
    }

    const { error } = await (session.supabase as any).rpc("submit_wwcc_submission", {
      submission_id: submissionId,
      assignment_id: parsed.data.assignment_id,
      legal_name: parsed.data.legal_name,
      wwcc_number: parsed.data.wwcc_number,
      expiry_date: parsed.data.expiry_date,
      document_file_id: fileRecordId,
      submission_notes: parsed.data.notes || null
    });
    if (error) {
      await service.from("file_records").delete().eq("id", fileRecordId);
      await deleteR2Object(bucket, objectPath, "WWCC submission rollback");
      console.error("WWCC submission RPC failed", { code: error.code, message: error.message, correlationId });
      return redirect("error", error.message ?? "The WWCC submission could not be saved.");
    }

    return redirect("success", "WWCC submission received and pending review.");
  } catch (cause) {
    console.error("Unexpected WWCC submission failure", { cause, correlationId });
    return redirect("error", `An unexpected error occurred. Reference ${correlationId}.`);
  }
};
