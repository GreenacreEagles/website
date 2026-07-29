import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const migration = read("supabase/migrations/20260729080638_admin_operations_hardening.sql");

test("admin overview is a permission-filtered quick-action grid", () => {
  const page = read("src/pages/admin/index.astro");
  for (const label of ["Add news article", "Add event", "Add social post", "Manage teams", "View canteen orders", "Search users", "Search wallets", "Review volunteers"]) assert.match(page, new RegExp(label, "i"));
  assert.match(page, /session\.permissions/);
  assert.doesNotMatch(page, /statistics|dashboard widgets/i);
});

test("canteen keeps payment and fulfilment independent and supports safe operations", () => {
  const page = read("src/pages/admin/canteen.astro");
  assert.match(page, /AdminSegmentedTabs/);
  assert.match(page, /section === "orders"/);
  assert.match(page, /section === "products"/);
  for (const action of ["Mark as paid", "Start preparing", "Mark ready for collection", "Mark collected", "Cancel"]) assert.match(page, new RegExp(action, "i"));
  for (const filter of ["category", "active", "availability", "voucher"]) assert.match(page, new RegExp(`name=["']${filter}["']`));
  assert.match(page, /AdminReorderForm/);
  assert.match(migration, /status_type in \('payment','fulfilment'\)/);
  assert.match(migration, /next_order='collected' and next_payment<>'paid'/);
  assert.match(migration, /order_row\.payment_status<>'paid'/);
  assert.match(migration, /if next_order<>order_row\.order_status or next_payment<>order_row\.payment_status/);
});

test("event registrants are scoped to the authorised detail page", () => {
  const list = read("src/pages/admin/events.astro");
  const detail = read("src/pages/admin/events/[id].astro");
  assert.doesNotMatch(list, /from\("event_registrations"\)/);
  assert.match(detail, /requirePermission\(Astro,\["events\.manage"\]\)/);
  assert.match(detail, /from\("event_registrations"\)/);
  assert.match(detail, /\.eq\("event_id",id\)/);
});

test("news and coaching slugs are generated uniquely on the server", () => {
  for (const path of ["src/pages/admin/news.astro", "src/pages/admin/coaching-resources.astro"]) assert.doesNotMatch(read(path), /name=["']slug["']/);
  const route = read("src/pages/api/admin/content-entry.ts");
  assert.match(route, /rpc\("generate_admin_slug"/);
  assert.match(route, /idResult\.success\?id:null/);
  assert.match(migration, /candidate:=left\(base,130-length\(suffix::text\)-1\)\|\|'-'\|\|suffix/);
  assert.match(migration, /app_private\.slugify\(target_title\)/);
});

test("social and coaching ordering cannot reorder a filtered subset", () => {
  const social = read("src/pages/admin/highlights.astro");
  const coaching = read("src/pages/admin/coaching-resources.astro");
  assert.match(social, /Social Profiles/);
  assert.match(social, /Social Posts/);
  assert.match(social, /canPosts && !q/);
  assert.match(coaching, /\{!q&&/);
  const form = read("src/components/AdminReorderForm.astro");
  assert.match(form, /dragstart/);
  assert.match(form, /Move up/);
  assert.match(form, /Move down/);
  assert.match(form, /Saving/);
});

test("teams, sponsors, wallets and secure user email routes retain server enforcement", () => {
  assert.match(read("src/pages/admin/teams.astro"), /searchedTeams/);
  const sponsor = read("src/pages/api/admin/sponsor.ts");
  assert.match(sponsor, /normalizeSponsorWebsite/);
  assert.match(sponsor, /protocol === "https:"/);
  const wallet = read("src/pages/api/admin/wallet-adjustment.ts");
  assert.match(wallet, /idempotency_key/);
  assert.match(wallet, /rpc\("adjust_wallet_balance"/);
  assert.match(read("src/pages/api/admin/wallet-status.ts"), /rpc\("set_wallet_status"/);
  assert.match(migration, /before_row\.status='closed'/);
  assert.match(migration, /wallet_row\.status <> 'active'|target_status not in \('active','frozen'\)/);
  const users = read("src/pages/admin/users/index.astro");
  assert.match(users, /rpc\("admin_user_directory"/);
  assert.match(migration, /join auth\.users u/);
  assert.match(migration, /has_permission\('users\.read'\)/);
  assert.match(migration, /child\.child_user_id is not null then null else u\.email/);
});

test("WWCC document access and review remain private and audited", () => {
  const documentRoute = read("src/pages/api/wwcc-document.ts");
  assert.match(documentRoute, /requireUser/);
  assert.match(documentRoute, /hasAnyPermission\(session\.permissions, \["wwcc\.view", "wwcc\.verify"\]\)/);
  assert.match(documentRoute, /writeAdminAudit/);
  assert.doesNotMatch(documentRoute, /publicUrl|getPublicUrl/);
  const review = read("src/pages/api/admin/wwcc-review.ts");
  assert.match(review, /review_wwcc_submission/);
  assert.match(read("src/pages/admin/volunteers.astro"), /clearance_type/);
});