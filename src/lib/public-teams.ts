import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "../types/database.types";
import { getPublicMediaUrl } from "./media";
import { PAGE_BOUNDS, clampLimit } from "./pagination";

export type PublicTeamSummary = {
  id: string; slug: string; name: string; division: string | null;
  competition: string | null; seasonName: string | null; summary: string | null; imageUrl: string | null;
};
export type PublicPlayerCard = {
  id: string; displayName: string; squadNumber: number | null; position: string | null; photoUrl: string | null;
};
export type PublicTeamStaffCard = {
  id: string; displayName: string; roleLabel: string; photoUrl: string | null;
};
export type PublicTeamDetail = PublicTeamSummary & {
  players: PublicPlayerCard[]; staff: PublicTeamStaffCard[];
};

type Context = { locals?: any };
type Client = SupabaseClient<Database>;

const teamSelect = "id,slug,name,division,summary,image_object_key,sort_order,seasons(name,year),competitions(name)";
const mapTeam = (row: any, context: Context): PublicTeamSummary => ({
  id: row.id, slug: row.slug, name: row.name,
  division: row.division ?? null, competition: row.competitions?.name ?? null,
  seasonName: row.seasons?.name ?? null, summary: row.summary ?? null,
  imageUrl: getPublicMediaUrl(row.image_object_key, context)
});

export async function getPublicTeams(client: Client, context: Context, limit?: number): Promise<{ activeTeamCount: number; teams: PublicTeamSummary[] }> {
  const boundedLimit = clampLimit(limit, PAGE_BOUNDS.teams);
  const { data, error } = await (client as any).from("teams").select(teamSelect).eq("status", "active").eq("public", true)
    .order("year", { referencedTable: "seasons", ascending: false })
    .order("sort_order").order("name")
    .limit(boundedLimit);
  if (error) throw error;
  const teams = (data ?? []).map((row: any) => mapTeam(row, context));

  // Skip the extra COUNT(*) round-trip when the page already holds every active team.
  if (teams.length < boundedLimit) {
    return { activeTeamCount: teams.length, teams };
  }
  const { count, error: countError } = await client.from("teams").select("id", { count: "exact", head: true }).eq("status", "active");
  if (countError) throw countError;
  return { activeTeamCount: count ?? teams.length, teams };
}

export async function getPublicTeam(
  client: Client,
  context: Context,
  slug: string,
  limits?: { squadLimit?: number; staffLimit?: number }
): Promise<PublicTeamDetail | null> {
  const { data: team, error } = await (client as any).from("teams").select(teamSelect)
    .eq("slug", slug).eq("status", "active").eq("public", true).maybeSingle();
  if (error) throw error;
  if (!team) return null;

  const squadLimit = clampLimit(limits?.squadLimit, PAGE_BOUNDS.teamSquad);
  const staffLimit = clampLimit(limits?.staffLimit, PAGE_BOUNDS.teamStaff);
  const [{ data: squad, error: squadError }, { data: staff, error: staffError }] = await Promise.all([
    (client as any).from("team_players")
      .select("id,squad_number,player_records(id,photo_object_key,photo_consent,registration_status,profiles:user_id(full_name,preferred_name))")
      .eq("team_id", team.id).eq("status", "active").order("squad_number").limit(squadLimit),
    (client as any).from("team_staff")
      .select("id,staff_role,profiles:user_id(full_name,preferred_name,public_photo_object_key,public_photo_consent)")
      .eq("team_id", team.id).eq("status", "active").order("staff_role").limit(staffLimit)
  ]);
  if (squadError || staffError) throw squadError ?? staffError;
  const players = (squad ?? []).filter((row: any) => row.player_records?.registration_status === "registered").map((row: any) => {
    const player = row.player_records;
    return {
      id: player.id,
      displayName: player.profiles?.preferred_name || player.profiles?.full_name || "Eagles player",
      squadNumber: row.squad_number ?? null,
      position: null,
      photoUrl: player.photo_consent ? getPublicMediaUrl(player.photo_object_key, context) : null
    };
  });
  const roleLabels: Record<string, string> = { coach: "Coach", team_manager: "Team Manager" };
  const publicStaff = (staff ?? []).map((row: any) => ({
    id: row.id,
    displayName: row.profiles?.preferred_name || row.profiles?.full_name || "Team staff",
    roleLabel: roleLabels[row.staff_role] ?? "Team staff",
    photoUrl: row.profiles?.public_photo_consent ? getPublicMediaUrl(row.profiles?.public_photo_object_key, context) : null
  }));
  return { ...mapTeam(team, context), players, staff: publicStaff };
}
