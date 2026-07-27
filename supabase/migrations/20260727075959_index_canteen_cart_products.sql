-- Cover the cart product foreign key for catalogue removal and checkout joins.
create index if not exists canteen_cart_items_product_id_idx
  on public.canteen_cart_items(product_id);
