export type WwccSubmissionStatus =
  | "pending"
  | "approved"
  | "rejected"
  | "resubmission_required"
  | "superseded";

export type WwccDisplayStatus =
  | "not_submitted"
  | "pending"
  | "approved"
  | "expiring"
  | "expired"
  | "rejected";

const dateOnly = (value: Date) => {
  const year = value.getUTCFullYear();
  const month = String(value.getUTCMonth() + 1).padStart(2, "0");
  const day = String(value.getUTCDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
};

export const wwccDisplayStatus = (
  submission: { status: WwccSubmissionStatus; expiry_date: string } | null | undefined,
  now = new Date()
): WwccDisplayStatus => {
  if (!submission) return "not_submitted";
  if (submission.status === "pending") return "pending";
  if (submission.status === "rejected" || submission.status === "resubmission_required") return "rejected";
  if (submission.status !== "approved") return "not_submitted";

  const today = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  const warningDate = new Date(today);
  warningDate.setUTCMonth(warningDate.getUTCMonth() + 3);
  if (submission.expiry_date < dateOnly(today)) return "expired";
  if (submission.expiry_date <= dateOnly(warningDate)) return "expiring";
  return "approved";
};

export const wwccStatusLabel = (status: WwccDisplayStatus) => ({
  not_submitted: "WWCC required",
  pending: "Pending review",
  approved: "Approved",
  expiring: "Expiring within 3 months",
  expired: "Expired",
  rejected: "Resubmission required"
})[status];
