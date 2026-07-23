import type { APIRoute } from "astro";
import { z } from "zod";
import { requireUser } from "@lib/auth/guards";
import { optionalUuidSchema, redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const optionalNumber = z.preprocess((value) => (value === "" ? null : Number(value)), z.number().int().min(0).max(99).nullable().optional());
const nullableText = (max = 2000) => z.preprocess((value) => (value === "" ? null : value), z.string().trim().max(max).nullable().optional());

const schema = z.object({
  team_id: uuidSchema,
  fixture_id: optionalUuidSchema,
  final_score_for: optionalNumber,
  final_score_against: optionalNumber,
  result: z.preprocess((value) => (value === "" ? null : value), z.enum(["win", "draw", "loss", "abandoned"]).nullable().optional()),
  highlights: nullableText(2500),
  improvement_notes: nullableText(2500),
  conduct_issues: nullableText(1500),
  injury_notes: nullableText(1500),
  private_notes: nullableText(2500),
  status: z.enum(["draft", "submitted"]).default("submitted")
});

export const POST: APIRoute = async (context) => {
  const session = await requireUser(context);
  if (!session) return context.redirect("/login/");

  const parsed = schema.safeParse(Object.fromEntries(await context.request.formData()));
  if (!parsed.success) return context.redirect(redirectWithMessage("/portal/teams/", "error", parsed.error.issues[0]?.message ?? "Match report could not be saved."));

  const data = parsed.data;
  const redirectPath = `/portal/teams/${data.team_id}/#match-reports`;
  const { error } = await session.supabase.from("match_reports").insert({
    fixture_id: data.fixture_id ?? null,
    team_id: data.team_id,
    author_id: session.user.id,
    final_score_for: data.final_score_for ?? null,
    final_score_against: data.final_score_against ?? null,
    result: data.result ?? null,
    highlights: data.highlights ?? null,
    improvement_notes: data.improvement_notes ?? null,
    conduct_issues: data.conduct_issues ?? null,
    injury_notes: data.injury_notes ?? null,
    private_notes: data.private_notes ?? null,
    status: data.status
  });

  return context.redirect(redirectWithMessage(redirectPath, error ? "error" : "success", error?.message ?? "Match report saved."));
};
