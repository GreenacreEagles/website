import assert from "node:assert/strict";
import test from "node:test";
import { wwccDisplayStatus, wwccStatusLabel } from "../src/lib/wwcc.ts";

const now = new Date("2026-07-28T12:00:00Z");

test("WWCC status handles missing, pending and rejected submissions", () => {
  assert.equal(wwccDisplayStatus(null, now), "not_submitted");
  assert.equal(wwccDisplayStatus({ status: "pending", expiry_date: "2030-01-01" }, now), "pending");
  assert.equal(wwccDisplayStatus({ status: "resubmission_required", expiry_date: "2030-01-01" }, now), "rejected");
});

test("WWCC status derives approved, expiring and expired from the expiry date", () => {
  assert.equal(wwccDisplayStatus({ status: "approved", expiry_date: "2027-01-01" }, now), "approved");
  assert.equal(wwccDisplayStatus({ status: "approved", expiry_date: "2026-10-28" }, now), "expiring");
  assert.equal(wwccDisplayStatus({ status: "approved", expiry_date: "2026-07-27" }, now), "expired");
});

test("WWCC display labels are clear", () => {
  assert.equal(wwccStatusLabel("not_submitted"), "WWCC required");
  assert.equal(wwccStatusLabel("expiring"), "Expiring within 3 months");
});
