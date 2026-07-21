export const ADMIN_PERMISSIONS = [
  "users.read",
  "users.manage",
  "roles.read",
  "roles.assign",
  "roles.review",
  "club_structure.manage",
  "audit.read"
] as const;

export const PORTAL_PERMISSIONS = [
  ...ADMIN_PERMISSIONS,
  "content.manage",
  "canteen.orders.manage",
  "volunteers.manage",
  "events.manage",
  "teams.read"
] as const;

export type PermissionKey = (typeof PORTAL_PERMISSIONS)[number] | "*";

export const hasAnyPermission = (permissions: Set<string>, required: string[]) =>
  permissions.has("*") || required.some((permission) => permissions.has(permission));

export const canAccessAdmin = (permissions: Set<string>) =>
  hasAnyPermission(permissions, [...ADMIN_PERMISSIONS]);
