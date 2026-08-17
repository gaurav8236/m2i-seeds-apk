-- ============================================================
-- Sprint 2 · Migration 004
-- DB constraints: price ≥ 0, stock ≥ 0, low_stock_limit ≥ 1
-- Risk: HIGH — will FAIL if dirty data exists
-- Run order: FOURTH (after fixing the 5 decimal stock rows)
-- ⚠️  Run pre-checks first. Fix violations, then add constraints.
-- ============================================================

-- PRE-CHECK 1: find negative or null selling prices
SELECT id, item_name, selling_price
FROM user_stock
WHERE selling_price < 0 OR selling_price IS NULL;

-- PRE-CHECK 2: find negative or decimal stock values
SELECT id, item_name, current_stock
FROM user_stock
WHERE current_stock < 0
   OR current_stock != FLOOR(current_stock);

-- PRE-CHECK 3: find low_stock_limit < 1
SELECT id, item_name, low_stock_limit
FROM user_stock
WHERE low_stock_limit < 1 OR low_stock_limit IS NULL;

-- ─────────────────────────────────────────────────────────────
-- Fix script for the 5 known decimal stock rows (from DB audit)
-- Round to nearest integer, floor to 0 if negative
-- ─────────────────────────────────────────────────────────────
UPDATE user_stock
SET current_stock = GREATEST(0, ROUND(current_stock))
WHERE current_stock != FLOOR(current_stock);

UPDATE user_stock
SET current_stock = 0
WHERE current_stock < 0;

UPDATE user_stock
SET low_stock_limit = 1
WHERE low_stock_limit < 1 OR low_stock_limit IS NULL;

UPDATE user_stock
SET selling_price = 0
WHERE selling_price < 0 OR selling_price IS NULL;

-- ─────────────────────────────────────────────────────────────
-- Add constraints (only after pre-checks return 0 rows)
-- ─────────────────────────────────────────────────────────────

ALTER TABLE user_stock
  ADD CONSTRAINT user_stock_selling_price_non_negative
  CHECK (selling_price >= 0);

ALTER TABLE user_stock
  ADD CONSTRAINT user_stock_current_stock_non_negative
  CHECK (current_stock >= 0);

-- Integer stock: stored as NUMERIC — enforce integer values
ALTER TABLE user_stock
  ADD CONSTRAINT user_stock_current_stock_integer
  CHECK (current_stock = FLOOR(current_stock));

ALTER TABLE user_stock
  ADD CONSTRAINT user_stock_low_stock_limit_min_one
  CHECK (low_stock_limit >= 1);

-- Verify
SELECT constraint_name
FROM information_schema.table_constraints
WHERE table_name = 'user_stock' AND constraint_type = 'CHECK'
ORDER BY constraint_name;
