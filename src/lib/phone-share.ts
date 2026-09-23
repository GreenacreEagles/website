type TicketShare = {
  title: string;
  typeName?: string | null;
  when?: string | null;
  venue?: string | null;
  code: string;
};

type VoucherShare = {
  label: string;
  detail?: string | null;
  value: string;
  validUntil?: string | null;
  code: string;
};

const lines = (parts: Array<string | null | undefined | false>) => parts.filter((part): part is string => Boolean(part)).join("\n");

export const ticketShareMessage = (ticket: TicketShare) =>
  lines([
    "Greenacre Eagles FC ticket",
    ticket.title,
    ticket.typeName,
    ticket.when,
    ticket.venue,
    `Ticket code: ${ticket.code}`,
    "Show this code at entry. It can only be used once."
  ]);

export const voucherShareMessage = (voucher: VoucherShare) =>
  lines([
    "Greenacre Eagles FC canteen voucher",
    voucher.label,
    voucher.detail,
    `${voucher.value} remaining`,
    voucher.validUntil ? `Valid until ${voucher.validUntil}` : null,
    `Voucher code: ${voucher.code}`,
    "Show this code at the canteen. It can only be used once."
  ]);
