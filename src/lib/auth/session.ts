import { createSupabaseServerClient } from "@lib/supabase/server";
import { PORTAL_PERMISSIONS } from "./permissions";
import type { Database } from "../../types/database.types";

type AstroContext = Parameters<typeof createSupabaseServerClient>[0];
type Profile = Database["public"]["Tables"]["profiles"]["Row"];

export type RoleAssignmentSummary = {
  id: string;
  status: string;
  starts_at: string;
  ends_at: string | null;
  reason: string | null;
  role: {
    id: string;
    key: string;
    name: string;
    description: string | null;
    is_sensitive: boolean;
  } | null;
  team: {
    id: string;
    name: string;
  } | null;
  season: {
    id: string;
    name: string;
  } | null;
};

export type PortalSession = {
  supabase: ReturnType<typeof createSupabaseServerClient>;
  user: {
    id: string;
    email?: string;
    created_at?: string;
  };
  profile: Profile;
  permissions: Set<string>;
  roleAssignments: RoleAssignmentSummary[];
  unreadNotifications: number;
};

const isActiveAssignment = (assignment: RoleAssignmentSummary) => {
  const now = Date.now();
  const starts = new Date(assignment.starts_at).getTime();
  const ends = assignment.ends_at ? new Date(assignment.ends_at).getTime() : Number.POSITIVE_INFINITY;
  return assignment.status === "active" && starts <= now && ends > now;
};

export const getPortalSession = async (context: AstroContext): Promise<PortalSession | null> => {
  const supabase = createSupabaseServerClient(context);
  const { data: userData, error: userError } = await supabase.auth.getUser();
  const user = userData.user;

  if (userError || !user) return null;

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", user.id)
    .single();

  if (profileError || !profile || profile.account_status !== "active") return null;

  const { data: assignments } = await supabase
    .from("user_role_assignments")
    .select("id,status,starts_at,ends_at,reason,roles(id,key,name,description,is_sensitive),teams(id,name),seasons(id,name)")
    .eq("user_id", user.id)
    .order("created_at", { ascending: false });

  const permissionEntries = await Promise.all(
    PORTAL_PERMISSIONS.map(async (permission) => {
      const { data } = await supabase.rpc("has_permission", { permission_key: permission });
      return [permission, data === true] as const;
    })
  );

  const permissions = new Set<string>();
  permissionEntries.forEach(([permission, allowed]) => {
    if (allowed) permissions.add(permission);
  });

  const { data: superAdmin } = await supabase.rpc("has_permission", { permission_key: "*" });
  if (superAdmin) permissions.add("*");

  const { count: unreadNotifications } = await supabase
    .from("notifications")
    .select("id", { count: "exact", head: true })
    .eq("recipient_id", user.id)
    .is("read_at", null);

  return {
    supabase,
    user: {
      id: user.id,
      email: user.email,
      created_at: user.created_at
    },
    profile,
    permissions,
    roleAssignments: ((assignments ?? []) as unknown as RoleAssignmentSummary[]).filter(isActiveAssignment),
    unreadNotifications: unreadNotifications ?? 0
  };
};

export const requirePortalSession = async (context: AstroContext) => {
  const session = await getPortalSession(context);
  if (!session) return null;
  return session;
};
