export const GLOBAL_ROLE_KEYS = [
  "general_user",
  "club_admin",
  "registrar",
  "volunteer",
  "content_editor",
  "event_manager",
  "merchandise_manager",
  "canteen_manager",
  "canteen_staff"
] as const;

export const TECHNICAL_ROLE_KEYS = ["super_administrator"] as const;
export const TEAM_POSITION_KEYS = ["player", "coach", "team_manager"] as const;

export type GlobalRoleKey = (typeof GLOBAL_ROLE_KEYS)[number];
export type TeamPositionKey = (typeof TEAM_POSITION_KEYS)[number];

/** Permissions that open the administration workspace. Operational fulfilment alone stays in the portal. */
export const ADMIN_PERMISSIONS = [
  "*",
  "users.read",
  "users.manage",
  "roles.read",
  "roles.assign",
  "roles.manage",
  "registrations.view",
  "registrations.manage",
  "team_memberships.manage",
  "club_structure.manage",
  "families.manage",
  "players.manage",
  "teams.manage",
  "team_posts.moderate",
  "match_reports.read",
  "match_reports.review",
  "content.view",
  "content.manage",
  "social_profiles.view",
  "social_profiles.manage",
  "social_posts.view",
  "social_posts.manage",
  "sponsors.manage",
  "sponsors.view",
  "canteen.manage",
  "canteen.products.manage",
  "canteen.reports.view",
  "canteen.orders.manage",
  "canteen.vouchers.manage",
  "canteen.vouchers.reverse",
  "wallet.read",
  "wallet.adjust",
  "wallet.vouchers.manage",
  "finance.read",
  "merchandise.view",
  "merchandise.manage",
  "merchandise.store_access",
  "shop.products.manage",
  "shop.orders.manage",
  "events.view",
  "events.manage",
  "volunteers.view",
  "volunteers.manage",
  "wwcc.view",
  "wwcc.verify",
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
  "canteen.orders.view",
  "canteen.orders.fulfil",
  "canteen.vouchers.redeem",
  "shop.products.view",
  "shop.orders.view",
  "shop.canteen.scan",
  "shop.canteen.redeem",
  "shop.merchandise.fulfil"
] as const;

export type PermissionKey = (typeof PORTAL_PERMISSIONS)[number];

export const hasAnyPermission = (permissions: Set<string>, required: readonly string[]) =>
  permissions.has("*") || required.some((permission) => permissions.has(permission));

export const canAccessAdmin = (permissions: Set<string>) =>
  hasAnyPermission(permissions, ADMIN_PERMISSIONS);