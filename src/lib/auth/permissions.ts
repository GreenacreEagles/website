export const ADMIN_PERMISSIONS = [
  "users.read",
  "users.manage",
  "roles.read",
  "roles.assign",
  "roles.review",
  "team_access.review",
  "team_members.manage",
  "club_structure.manage",
  "families.manage",
  "players.manage",
  "teams.manage",
  "team_posts.create",
  "team_posts.moderate",
  "match_reports.read",
  "match_reports.review",
  "content.manage",
  "social_profiles.view",
  "social_profiles.manage",
  "social_posts.view",
  "social_posts.manage",
  "sponsors.manage",
  "canteen.manage",
  "canteen.orders.manage",
  "canteen.vouchers.manage",
  "canteen.vouchers.reverse",
  "wallet.read",
  "wallet.adjust",
  "wallet.vouchers.manage",
  "finance.read",
  "merchandise.manage",
  "merchandise.store_access",
  "events.manage",
  "events.orders.read",
  "events.tickets.scan",
  "events.tickets.redeem",
  "volunteers.manage",
  "communications.manage",
  "files.manage",
  "coaching_resources.manage",
  "children.manage"
] as const;

export const PORTAL_PERMISSIONS = [
  ...ADMIN_PERMISSIONS,
  "families.invite",
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
