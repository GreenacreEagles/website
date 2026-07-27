export type MerchandiseCartItem = {
  cart_item_id: string;
  variant_id: string;
  product_id: string;
  product_name: string;
  product_description: string | null;
  category: string;
  image_url: string | null;
  image_object_key: string | null;
  variant_label: string | null;
  sku: string | null;
  unit_price_cents: number;
  quantity: number;
  stock_quantity: number;
  is_available: boolean;
  availability_message: string | null;
};

export const loadMerchandiseCart = async (supabase: any): Promise<{ items: MerchandiseCartItem[]; error: string | null }> => {
  const { data, error } = await supabase.rpc("get_merchandise_cart");
  return {
    items: (data ?? []) as MerchandiseCartItem[],
    error: error?.message ?? null
  };
};

export const merchandiseCartTotals = (items: MerchandiseCartItem[]) => ({
  itemCount: items.length,
  quantity: items.reduce((total, item) => total + item.quantity, 0),
  totalCents: items.reduce((total, item) => total + item.unit_price_cents * item.quantity, 0),
  canCheckout: items.length > 0 && items.every((item) => item.is_available)
});

export const merchandiseOrderLabel = (status: string) => ({
  awaiting_payment: "Order placed",
  paid: "Payment received",
  processing: "Preparing",
  awaiting_stock: "Awaiting stock",
  ready_for_pickup: "Ready for collection",
  shipped: "Shipped",
  collected: "Collected",
  completed: "Completed",
  cancelled: "Cancelled",
  refunded: "Refunded",
  partially_refunded: "Partially refunded"
}[status] ?? status.replaceAll("_", " "));

export const merchandisePaymentLabel = (status: string) => ({
  awaiting_payment: "Awaiting payment",
  paid: "Paid",
  cancelled: "Cancelled",
  refunded: "Refunded",
  partially_refunded: "Partially refunded"
}[status] ?? status.replaceAll("_", " "));

export const merchandisePaymentMethodLabel = (method: string) =>
  method === "pay_at_club" ? "Pay at the club" : method.replaceAll("_", " ");

export const friendlyMerchandiseError = (message?: string | null) => {
  if (!message) return "The store could not update your cart. Please try again.";
  const allowed = [
    "Authentication required",
    "Your cart is empty",
    "That merchandise item is not available",
    "An item in your cart is no longer available",
    "Quantity cannot be less than zero",
    "The maximum quantity for one item is 50"
  ];
  if (allowed.includes(message) || message.startsWith("Only ")) return message;
  return "The store could not complete that request. Please review your cart and try again.";
};
