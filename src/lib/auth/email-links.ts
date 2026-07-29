export const emailOtpTypes = ["email", "recovery"] as const;
export type SupportedEmailOtpType = (typeof emailOtpTypes)[number];

export const parseEmailOtpType = (value: string | null): SupportedEmailOtpType | null =>
  emailOtpTypes.includes(value as SupportedEmailOtpType) ? value as SupportedEmailOtpType : null;

export const confirmationDestination = (type: SupportedEmailOtpType) =>
  type === "recovery" ? "/reset-password/" : "/login/?success=Your+email+has+been+confirmed.+You+can+now+sign+in.";
