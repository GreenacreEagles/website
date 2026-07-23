import type { APIRoute } from "astro";
import { z } from "zod";
import { requirePermission } from "@lib/auth/guards";
import { redirectWithMessage, uuidSchema } from "@lib/forms";

export const prerender = false;

const boolFromCheckbox = z.preprocess((value) => value === "on" || value === "true", z.boolean());
const optionalDate = z.preprocess((value) => (value === "" ? null : value), z.string().nullable().optional());

const schemas = {
  family: z.object({
    name: z.string().trim().min(2).max(140)
  }),
  familyMember: z.object({
    family_id: uuidSchema,
    user_id: uuidSchema,
    relationship: z.enum(["parent", "guardian", "carer", "child", "player", "dependent", "sibling", "adult_player"]),
    is_primary_guardian: boolFromCheckbox,
    can_manage: boolFromCheckbox,
    can_spend: boolFromCheckbox,
    spending_limit: z.preprocess((value) => (value === "" ? null : Math.round(Number(value || 0) * 100)), z.number().int().min(0).nullable().optional()),
    status: z.enum(["pending", "active", "revoked"]).default("active")
  }),
  player: z.object({
    user_id: uuidSchema,
    season_id: uuidSchema,
    registration_status: z.enum(["not_started", "pending", "registered", "transferred", "withdrawn"]),
    photo_consent: boolFromCheckbox,
    external_registration_ref: z.string().trim().max(120).optional()
  }),
  teamPlayer: z.object({
    team_id: uuidSchema,
    player_id: uuidSchema,
    squad_number: z.preprocess((value) => (value === "" ? null : Number(value)), z.number().int().min(0).max(999).nullable().optional()),
    starts_on: optionalDate,
    ends_on: optionalDate,
    status: z.enum(["active", "inactive", "left"]).default("active")
  })
};

type Action = keyof typeof schemas;

const actionPermissions: Record<Action, string[]> = {
  family: ["families.manage"],
  familyMember: ["families.manage"],
  player: ["players.manage"],
  teamPlayer: ["players.manage"]
};

export const POST: APIRoute = async (context) => {
  const form = Object.fromEntries(await context.request.formData());
  const action = form.action as Action;
  const schema = schemas[action];
  if (!schema) return context.redirect(redirectWithMessage("/admin/players/", "error", "Unknown family action."));

  const session = await requirePermission(context, actionPermissions[action]);
  if (!session) return context.redirect("/admin/");

  const parsed = schema.safeParse(form);
  if (!parsed.success) {
    return context.redirect(redirectWithMessage("/admin/players/", "error", parsed.error.issues[0]?.message ?? "Check the form details."));
  }

  const data = parsed.data as any;
  let error: { message: string } | null = null;
  let success = "Saved.";

  if (action === "family") {
    ({ error } = await session.supabase.from("families").insert({ name: data.name, created_by: session.user.id }));
    success = "Family created.";
  } else if (action === "familyMember") {
    ({ error } = await session.supabase.from("family_members").insert({
      family_id: data.family_id,
      user_id: data.user_id,
      relationship: data.relationship,
      is_primary_guardian: data.is_primary_guardian,
      can_manage: data.can_manage,
      can_spend: data.can_spend,
      spending_limit_cents: data.spending_limit,
      status: data.status,
      invited_by: session.user.id,
      accepted_at: data.status === "active" ? new Date().toISOString() : null
    }));
    success = "Family member linked.";
  } else if (action === "player") {
    ({ error } = await session.supabase.from("player_records").insert({
      user_id: data.user_id,
      season_id: data.season_id,
      registration_status: data.registration_status,
      photo_consent: data.photo_consent,
      external_registration_ref: data.external_registration_ref || null
    }));
    success = "Player record created.";
  } else if (action === "teamPlayer") {
    ({ error } = await session.supabase.from("team_players").insert({
      team_id: data.team_id,
      player_id: data.player_id,
      squad_number: data.squad_number,
      starts_on: data.starts_on,
      ends_on: data.ends_on,
      status: data.status
    }));
    success = "Player linked to team.";
  }

  return context.redirect(redirectWithMessage("/admin/players/", error ? "error" : "success", error?.message ?? success));
};
