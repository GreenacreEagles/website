export const ADMIN_PERMISSIONS = [
  "users.read",
  "users.manage",
  "roles.read",
  "roles.assign",
  "roles.review",
  "club_structure.manage",
  "audit.read",
  "families.manage",
  "players.manage",
  "teams.manage",
  "match_reports.read",
  "match_reports.review",
  "content.manage",
  "sponsors.manage",
  "canteen.manage",
  "canteen.orders.manage",
  "canteen.vouchers.manage",
  "wallet.read",
  "wallet.adjust",
  "merchandise.manage",
  "events.manage",
  "volunteers.manage",
  "communications.manage",
  "settings.manage",
  "files.manage",
  "coaching_resources.manage"
] as const;

export const PORTAL_PERMISSIONS = [
  ...ADMIN_PERMISSIONS,
  "teams.read",
  "coaching_resources.read",
  "match_reports.submit",
  "canteen.vouchers.redeem",
  "canteen.vouchers.reverse"
] as const;

export type PermissionKey = (typeof PORTAL_PERMISSIONS)[number] | "*";

export const hasAnyPermission = (permissions: Set<string>, required: string[]) =>
  permissions.has("*") || required.some((permission) => permissions.has(permission));

export const canAccessAdmin = (permissions: Set<string>) =>
  hasAnyPermission(permissions, [...ADMIN_PERMISSIONS]);
