export const formatDate = (value?: string | null) => {
  if (!value) return "Not set";
  return new Intl.DateTimeFormat("en-AU", { day: "2-digit", month: "short", year: "numeric" }).format(new Date(value));
};

export const formatDateTime = (value?: string | null) => {
  if (!value) return "Not set";
  return new Intl.DateTimeFormat("en-AU", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit"
  }).format(new Date(value));
};

const plainLabels: Record<string, string> = {
  user: "Wallet",
  manual: "Pay at the club",
  specific_product: "Item voucher",
  fixed_amount: "Voucher",
  declining_balance: "Voucher",
  category: "Category voucher",
  meal_deal: "Meal deal",
  general_user: "Member"
};

export const statusLabel = (value?: string | null) => {
  if (!value) return "Unknown";
  const known = plainLabels[value];
  if (known) return known;
  const words = value.replaceAll("_", " ");
  return words.charAt(0).toUpperCase() + words.slice(1);
};

export const formatMoney = (cents?: number | null) =>
  new Intl.NumberFormat("en-AU", { style: "currency", currency: "AUD" }).format((cents ?? 0) / 100);
