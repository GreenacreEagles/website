import { canAccessAdmin, hasAnyPermission } from "./permissions";
import { getPortalSession } from "./session";
import { createSupabaseServerClient } from "@lib/supabase/server";
import type { PortalSession } from "./session";
import { recordServerTiming } from "@lib/server-timing";

type GuardContext = Parameters<typeof getPortalSession>[0];

const isApiRequest = (context: GuardContext) =>
  new URL(context.request.url).pathname.startsWith("/api/");

export const requireActionPermission = async (
  context: GuardContext,
  permissions: string[],
  scope: { teamId?: string | null; seasonId?: string | null } = {}
) => {
  const supabase = createSupabaseServerClient(context);
  const authStartedAt = performance.now();
  const { data: userData, error: userError } = await supabase.auth.getUser();
  recordServerTiming(context, "auth", authStartedAt);
  const user = userData.user;
  if (userError || !user) return null;

  const permissionStartedAt = performance.now();
  const { data: allowed, error: permissionError } = await supabase.rpc("has_any_permission", {
    required_keys: permissions,
    target_team_id: scope.teamId ?? undefined,
    target_season_id: scope.seasonId ?? undefined
  });
  recordServerTiming(context, "permission", permissionStartedAt);

  if (permissionError || allowed !== true) return null;

  return {
    supabase,
    user: {
      id: user.id,
      email: user.email,
      created_at: user.created_at
    }
  };
};

export const requireUser = async (context: GuardContext) => {
  const session = await getPortalSession(context);
  return session;
};

export const requireAdmin = async (context: GuardContext) => {
  const session = await getPortalSession(context);
  if (!session || session.isChildAccount || !canAccessAdmin(session.permissions)) return null;
  return session;
};

export const requirePermission = async (context: GuardContext, permissions: string[]) => {
  // API handlers need one authoritative permission decision, not the complete
  // navigation context. The cast preserves the long-standing handler interface;
  // API handlers only consume `supabase` and `user`.
  if (isApiRequest(context)) {
    return (await requireActionPermission(context, permissions)) as PortalSession | null;
  }

  const session = await getPortalSession(context);
  if (!session || session.isChildAccount || !hasAnyPermission(session.permissions, permissions)) return null;
  return session;
};
