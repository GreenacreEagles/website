import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "../types/database.types";
import { getPublicMediaUrl } from "./media";

export type PublicTeamSummary = {
  id: string; slug: string; name: string; ageGroup: string | null; division: string | null;
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

const teamSelect = "id,slug,name,division,summary,image_object_key,sort_order,seasons(name,year),age_groups(name,sort_order),competitions(name)";
const mapTeam = (row: any, context: Context): PublicTeamSummary => ({
  id: row.id, slug: row.slug, name: row.name, ageGroup: row.age_groups?.name ?? null,
  division: row.division ?? null, competition: row.competitions?.name ?? null,
  seasonName: row.seasons?.name ?? null, summary: row.summary ?? null,
  imageUrl: getPublicMediaUrl(row.image_object_key, context)
});

export async function getPublicTeams(client: Client, context: Context): Promise<{ activeTeamCount: number; teams: PublicTeamSummary[] }> {
  const [{ count, error: countError }, { data, error }] = await Promise.all([
    client.from("teams").select("id", { count: "exact", head: true }).eq("status", "active"),
    (client as any).from("teams").select(teamSelect).eq("status", "active").eq("public", true)
      .order("year", { referencedTable: "seasons", ascending: false })
      .order("sort_order").order("name")
  ]);
  if (countError || error) throw countError ?? error;
  return { activeTeamCount: count ?? 0, teams: (data ?? []).map((row: any) => mapTeam(row, context)) };
}

export async function getPublicTeam(client: Client, context: Context, slug: string): Promise<PublicTeamDetail | null> {
  const { data: team, error } = await (client as any).from("teams").select(teamSelect)
    .eq("slug", slug).eq("status", "active").eq("public", true).maybeSingle();
  if (error) throw error;
  if (!team) return null;

  const [{ data: squad, error: squadError }, { data: staff, error: staffError }] = await Promise.all([
    (client as any).from("team_players")
      .select("id,squad_number,player_records(id,photo_object_key,photo_consent,registration_status,profiles:user_id(full_name,preferred_name))")
      .eq("team_id", team.id).eq("status", "active").order("squad_number"),
    (client as any).from("team_staff")
      .select("id,staff_role,profiles:user_id(full_name,preferred_name,public_photo_object_key,public_photo_consent)")
      .eq("team_id", team.id).eq("status", "active").order("staff_role")
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
  const roleLabels: Record<string, string> = { coach: "Coach", assistant_coach: "Assistant coach", team_manager: "Team manager", trainer: "Trainer" };
  const publicStaff = (staff ?? []).map((row: any) => ({
    id: row.id,
    displayName: row.profiles?.preferred_name || row.profiles?.full_name || "Team staff",
    roleLabel: roleLabels[row.staff_role] ?? "Team staff",
    photoUrl: row.profiles?.public_photo_consent ? getPublicMediaUrl(row.profiles?.public_photo_object_key, context) : null
  }));
  return { ...mapTeam(team, context), players, staff: publicStaff };
}
