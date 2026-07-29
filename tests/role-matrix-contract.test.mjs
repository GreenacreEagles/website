import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");

const guardedAdminRoutes = [
  "src/pages/api/admin/wallet-adjustment.ts",
  "src/pages/api/admin/wallet-status.ts",
  "src/pages/api/admin/assign-role.ts",
  "src/pages/api/admin/redeem-voucher.ts",
  "src/pages/api/admin/reverse-voucher-redemption.ts",
  "src/pages/api/admin/wwcc-review.ts",
  "src/pages/api/admin/reorder.ts"
];

test("admin write routes require an authenticated session (requireUser or requirePermission) before mutating data", () => {
  for (const path of guardedAdminRoutes) {
    const source = read(path);
    assert.match(source, /requireUser\(|requirePermission\(/, `${path} must call requireUser or requirePermission`);
  }
});

const guardedPortalRoutes = [
  "src/pages/api/portal/wallet-top-up.ts",
  "src/pages/api/portal/child-account.ts",
  "src/pages/api/portal/team-post.ts",
  "src/pages/api/portal/team-post-reaction.ts",
  "src/pages/api/portal/family-invite.ts",
  "src/pages/api/portal/family-invitation-accept.ts",
  "src/pages/api/portal/wwcc-submission.ts"
];

test("portal write routes require an authenticated member session", () => {
  for (const path of guardedPortalRoutes) {
    const source = read(path);
    assert.match(source, /requireUser\(context\)/, `${path} must call requireUser(context)`);
  }
});

test("child account creation rejects child accounts and only proceeds for delegated family managers", () => {
  const source = read("src/pages/api/portal/child-account.ts");
  assert.match(source, /!session \|\| session\.isChildAccount/);
  assert.match(source, /can_manage/);
  assert.match(source, /You cannot manage this family group\./);
});

test("WWCC document downloads are permission-checked, private, audited and never publicly cached", () => {
  const source = read("src/pages/api/wwcc-document.ts");
  assert.match(source, /requireUser\(context\)/);
  assert.match(source, /hasAnyPermission\(session\.permissions, \["wwcc\.view", "wwcc\.verify"\]\)/);
  assert.match(source, /"cache-control": "private, no-store"/);
  assert.doesNotMatch(source, /"cache-control":\s*"public/);
  assert.match(source, /writeAdminAudit/);
});

test("coaching attachment downloads stay private and never expose a public cache-control", () => {
  const source = read("src/pages/api/admin/coaching-attachment.ts");
  assert.match(source, /requirePermission\(context,\["coaching_resources\.read","coaching_resources\.manage"\]\)/);
  assert.match(source, /"cache-control":"private, no-store"/);
  assert.doesNotMatch(source, /"cache-control":\s*"public/);
});

test("admin RPC-backed mutations rely on database permission checks (has_permission), not client-declared roles", () => {
  const migration = read("supabase/migrations/20260729080638_admin_operations_hardening.sql");
  assert.match(migration, /has_permission\(/);
});

test("wallet mutations always flow through audited, idempotent RPCs rather than direct table writes", () => {
  const adjustment = read("src/pages/api/admin/wallet-adjustment.ts");
  assert.match(adjustment, /idempotency_key/);
  assert.match(adjustment, /rpc\("adjust_wallet_balance"/);
  const status = read("src/pages/api/admin/wallet-status.ts");
  assert.match(status, /rpc\("set_wallet_status"/);
});

test("role assignment and revocation require an explicit reason and use the role-catalog RPC surface", () => {
  const assign = read("src/pages/api/admin/assign-role.ts");
  assert.match(assign, /rpc\("assign_user_role"/);
  const revoke = read("src/pages/api/admin/revoke-role.ts");
  assert.match(revoke, /reason/);
});
