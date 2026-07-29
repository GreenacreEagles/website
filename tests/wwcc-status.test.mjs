import assert from "node:assert/strict";
import test from "node:test";
import { volunteerWorkflowLabel, volunteerWorkflowStage, wwccDisplayStatus, wwccStatusLabel } from "../src/lib/wwcc.ts";

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

test("volunteer workflow requires adult confirmation before WWCC details", () => {
  assert.equal(volunteerWorkflowStage({ hasAssignment: false, adultConfirmed: false, wwccStatus: "not_submitted" }), "not_requested");
  assert.equal(volunteerWorkflowStage({ hasAssignment: true, adultConfirmed: false, wwccStatus: "not_submitted" }), "adult_confirmation_required");
  assert.equal(volunteerWorkflowStage({ hasAssignment: true, adultConfirmed: true, wwccStatus: "not_submitted" }), "wwcc_details_required");
  assert.equal(volunteerWorkflowStage({ hasAssignment: true, adultConfirmed: true, wwccStatus: "pending" }), "pending_review");
  assert.equal(volunteerWorkflowStage({ hasAssignment: true, adultConfirmed: false, wwccStatus: "approved" }), "approved");
  assert.equal(volunteerWorkflowLabel("adult_confirmation_required"), "Adult confirmation required");
});
