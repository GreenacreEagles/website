-- Preserve historical unified-shop rows, but close the combined ordering API.
-- Canteen and merchandise continue through their established dedicated tables
-- and RPCs.
revoke execute on function public.checkout_shop_cart(text, text) from authenticated;
revoke execute on function public.redeem_shop_collection(text) from authenticated;
revoke select, insert, update, delete on public.shop_cart_items from authenticated;
