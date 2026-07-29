import { createSupabaseServerClient } from "@lib/supabase/server";
import { recordServerTiming } from "@lib/server-timing";
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
  isChildAccount: boolean;
};

const isActiveAssignment = (assignment: RoleAssignmentSummary) => {
  const now = Date.now();
  const starts = new Date(assignment.starts_at).getTime();
  const ends = assignment.ends_at ? new Date(assignment.ends_at).getTime() : Number.POSITIVE_INFINITY;
  return assignment.status === "active" && starts <= now && ends > now;
};

type PortalContextResult = {
  user_id: string;
  profile: Profile | null;
  permission_keys: string[];
  role_assignments: RoleAssignmentSummary[];
  unread_notifications: number;
  is_child_account: boolean;
  child_login_disabled: boolean;
};

const requestSessions = new WeakMap<object, Promise<PortalSession | null>>();

/**
 * Consolidated per-request loader: one auth check + one `get_portal_context` RPC gives the
 * user, profile, roles, permissions, unread notification count, and child-account flag,
 * memoised per request. Mutation routes should call requireUser/requirePermission (which use
 * this cache) rather than re-fetching full page data lists (teams, wallets, notifications, etc.)
 * that the portal pages already load separately.
 */
export const getPortalSession = async (context: AstroContext): Promise<PortalSession | null> => {
  const requestKey = context as object;
  const existing = requestSessions.get(requestKey);
  if (existing) return existing;

  const pending = loadPortalSession(context);
  requestSessions.set(requestKey, pending);
  return pending;
};

const loadPortalSession = async (context: AstroContext): Promise<PortalSession | null> => {
  const supabase = createSupabaseServerClient(context);
  const authStartedAt = performance.now();
  const { data: userData, error: userError } = await supabase.auth.getUser();
  recordServerTiming(context, "auth", authStartedAt);
  const user = userData.user;

  if (userError || !user) return null;

  const contextStartedAt = performance.now();
  const { data, error } = await supabase.rpc("get_portal_context");
  recordServerTiming(context, "portal-context", contextStartedAt);
  const portalContext = data as unknown as PortalContextResult | null;
  const profile = portalContext?.profile;

  if (
    error ||
    !portalContext ||
    portalContext.user_id !== user.id ||
    !profile ||
    profile.account_status !== "active" ||
    portalContext.child_login_disabled
  ) {
    return null;
  }

  return {
    supabase,
    user: {
      id: user.id,
      email: user.email,
      created_at: user.created_at
    },
    profile,
    permissions: new Set(portalContext.permission_keys ?? []),
    roleAssignments: (portalContext.role_assignments ?? []).filter(isActiveAssignment),
    unreadNotifications: portalContext.unread_notifications ?? 0,
    isChildAccount: portalContext.is_child_account
  };
};

export const requirePortalSession = async (context: AstroContext) => {
  const session = await getPortalSession(context);
  if (!session) return null;
  return session;
};
