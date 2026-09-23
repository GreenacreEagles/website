import test from "node:test";
import assert from "node:assert/strict";
import { ticketShareMessage, voucherShareMessage } from "../src/lib/phone-share.ts";

test("ticket share message includes the event and a single-use code", () => {
  const message = ticketShareMessage({
    title: "Season launch",
    typeName: "Adult",
    when: "Sat, 4 Apr 2026, 6:00 pm",
    venue: "Roberts Park",
    code: "GE1234"
  });
  assert.match(message, /Greenacre Eagles FC ticket/);
  assert.match(message, /Season launch/);
  assert.match(message, /Ticket code: GE1234/);
  assert.match(message, /used once/);
});

test("voucher share message includes the remaining value and code", () => {
  const message = voucherShareMessage({
    label: "fixed amount",
    detail: "Volunteer meal",
    value: "$10.00",
    validUntil: "04 Apr 2026",
    code: "ABC123"
  });
  assert.match(message, /canteen voucher/);
  assert.match(message, /\$10\.00 remaining/);
  assert.match(message, /Voucher code: ABC123/);
  assert.match(message, /used once/);
});
