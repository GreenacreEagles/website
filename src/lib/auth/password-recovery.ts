import { z } from "zod";

const recoveryPasswordSchema = z.object({
  password: z.string().min(8, "Use a password of at least 8 characters.").max(200),
  confirmPassword: z.string().min(8, "Use a password of at least 8 characters.").max(200)
}).refine((value) => value.password === value.confirmPassword, {
  message: "Passwords do not match.",
  path: ["confirmPassword"]
});

export const validateRecoveryPasswords = (value: unknown) => recoveryPasswordSchema.safeParse(value);
