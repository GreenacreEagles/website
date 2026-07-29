import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");
test("child navigation is restricted to operational member pages", async () => { const source=await read("src/layouts/PortalLayout.astro"); assert.match(source,/isChildAccount/); assert.match(source,/Family groups/); assert.match(source,/Canteen Staff/); });
test("wallet hides internal id and QR is disclosed on request", async () => { const source=await read("src/pages/portal/vouchers.astro"); assert.doesNotMatch(source,/>Wallet ID</); assert.match(source,/Show wallet QR code/); assert.doesNotMatch(source,/wallet.displayCode/); });
test("team board exposes tabs and fixed yes-no polls", async () => { const page=await read("src/pages/portal/teams/[id].astro"); const api=await read("src/pages/api/portal/team-post.ts"); assert.match(page,/Team Posts/); assert.match(page,/Match Reports/); assert.match(page,/Squad List/); assert.match(api,/["Yes", "No"]/); });
test("volunteer workflow collects required NSW record fields", async () => { const page=await read("src/pages/portal/roles.astro"); for(const field of ["date_of_birth","wwcc_number","expiry_date","clearance_type"]) assert.match(page,new RegExp(field)); assert.match(page,/not authoritative proof/); });

test("volunteer request requires explicit adult confirmation in UI and API", async () => {
  const page=await read("src/pages/portal/roles.astro");
  const api=await read("src/pages/api/portal/volunteer-request.ts");
  assert.match(page,/I confirm that I am 18 years of age or older/);
  assert.match(page,/name="adult_confirmation"/);
  assert.match(page,/Submit volunteer request/);
  assert.match(api,/adultConfirmation/);
  assert.match(api,/adult_confirmation: adultConfirmation/);
});
