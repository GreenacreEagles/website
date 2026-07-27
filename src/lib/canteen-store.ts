export type CanteenCartItem = {
  cart_item_id: string;
  product_id: string;
  product_name: string;
  product_description: string | null;
  category_name: string;
  image_url: string | null;
  image_object_key: string | null;
  unit_price_cents: number;
  quantity: number;
  stock_quantity: number | null;
  dietary_info: string[];
  allergen_info: string[];
  is_available: boolean;
  availability_message: string | null;
};

export const loadCanteenCart = async (supabase: any): Promise<{ items: CanteenCartItem[]; error: string | null }> => {
  const { data, error } = await supabase.rpc("get_canteen_cart");
  return { items: (data ?? []) as CanteenCartItem[], error: error?.message ?? null };
};

export const canteenCartTotals = (items: CanteenCartItem[]) => ({
  itemCount: items.length,
  quantity: items.reduce((total, item) => total + item.quantity, 0),
  subtotalCents: items.reduce((total, item) => total + item.unit_price_cents * item.quantity, 0),
  canCheckout: items.length > 0 && items.every((item) => item.is_available)
});

export const canteenOrderLabel = (status: string) => ({
  draft: "Draft", awaiting_payment: "Order placed", paid: "Payment received",
  accepted: "Order placed", preparing: "Preparing", ready_for_pickup: "Ready for collection",
  collected: "Collected", cancelled: "Cancelled", refunded: "Refunded",
  partially_refunded: "Partially refunded", expired: "Expired"
}[status] ?? status.replaceAll("_", " "));

export const canteenPaymentLabel = (status: string) => ({
  unpaid: "Awaiting payment", awaiting_payment: "Awaiting payment", paid: "Paid",
  partially_refunded: "Partially refunded", refunded: "Refunded"
}[status] ?? status.replaceAll("_", " "));

export const friendlyCanteenError = (message?: string | null) => {
  if (!message) return "The canteen store could not complete that request. Please try again.";
  const safe = ["Authentication required", "Your cart is empty", "That canteen item is not available",
    "An item in your cart is no longer available", "Quantity cannot be less than zero",
    "The maximum quantity for one item is 50", "A selected voucher is no longer available",
    "A selected voucher does not match an available cart item", "Wallet not available",
    "Insufficient wallet balance", "Choose a wallet for canteen credit"];
  if (safe.includes(message) || message.startsWith("Only ") || message.startsWith("Maximum quantity")) return message;
  return "The canteen store could not complete that request. Review your cart and benefits, then try again.";
};
