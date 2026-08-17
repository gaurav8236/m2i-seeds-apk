-- ============================================================
-- Sprint 2 · Migration 001
-- ON DELETE CASCADE on user_stock.product_id
-- Risk: LOW — no data changes, safe to run on live DB
-- Run order: FIRST (no dependencies)
-- ============================================================

-- Drop the existing FK constraint (name may vary — check yours with
--   SELECT constraint_name FROM information_schema.table_constraints
--   WHERE table_name = 'user_stock' AND constraint_type = 'FOREIGN KEY';
-- then replace the name below)
ALTER TABLE user_stock
  DROP CONSTRAINT IF EXISTS user_stock_product_id_fkey;

-- Re-add with CASCADE so orphan stock rows auto-clean when a product is deleted
ALTER TABLE user_stock
  ADD CONSTRAINT user_stock_product_id_fkey
  FOREIGN KEY (product_id)
  REFERENCES products(id)
  ON DELETE CASCADE;

-- Verify
SELECT constraint_name, delete_rule
FROM information_schema.referential_constraints
WHERE constraint_name = 'user_stock_product_id_fkey';
