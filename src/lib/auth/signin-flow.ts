import { z } from "zod";
import { safeAuthReturnPath } from "../forms.ts";

const schema = z.object({
  email: z.string().trim().min(3),
  password: z.string().min(1),
  returnTo: z.string().optional()
});

const usernameToEmail = (value: string) =>
  value.includes("@") ? value : `${value.toLowerCase()}@children.greenacre-eagles.local`;

type VerificationResult = { success: boolean; error?: string };
type SignInResult = { success: boolean };
type Dependencies = {
  verify: () => Promise<VerificationResult>;
  signIn: (credentials: { email: string; password: string }) => Promise<SignInResult>;
};

type SignInFlowResult =
  | { success: true; status: 303; location: string }
  | { success: false; status: 303; error: string };

export const runSignInFlow = async (formData: FormData, dependencies: Dependencies): Promise<SignInFlowResult> => {
  const verification = await dependencies.verify();
  if (!verification.success) {
    return { success: false, status: 303, error: verification.error ?? "Verification failed. Please try again." };
  }

  const parsed = schema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return { success: false, status: 303, error: "Enter your email and password." };

  const result = await dependencies.signIn({
    email: usernameToEmail(parsed.data.email),
    password: parsed.data.password
  });
  if (!result.success) {
    return { success: false, status: 303, error: "Sign in failed. Check your details and try again." };
  }

  return { success: true, status: 303, location: safeAuthReturnPath(parsed.data.returnTo) };
};
