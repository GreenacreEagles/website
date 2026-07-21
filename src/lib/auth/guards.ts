import { canAccessAdmin, hasAnyPermission } from "./permissions";
import { getPortalSession } from "./session";

type GuardContext = Parameters<typeof getPortalSession>[0];

export const requireUser = async (context: GuardContext) => {
  const session = await getPortalSession(context);
  return session;
};

export const requireAdmin = async (context: GuardContext) => {
  const session = await getPortalSession(context);
  if (!session || !canAccessAdmin(session.permissions)) return null;
  return session;
};

export const requirePermission = async (context: GuardContext, permissions: string[]) => {
  const session = await getPortalSession(context);
  if (!session || !hasAnyPermission(session.permissions, permissions)) return null;
  return session;
};
