-- ============================================================
-- Sprint 2 · Migration 002
-- transaction_type column on past_bills
-- Risk: MEDIUM — backfill required before adding NOT NULL
-- Run order: SECOND (after 001)
-- ============================================================

-- Step 1: Add column as nullable first
ALTER TABLE past_bills
  ADD COLUMN IF NOT EXISTS transaction_type TEXT;

-- Step 2: Backfill all existing rows
--   is_credit = true  → 'credit'  (shopkeeper gave goods on credit)
--   is_credit = false → 'sale'    (cash/UPI sale)
UPDATE past_bills
SET transaction_type = CASE
  WHEN is_credit = TRUE THEN 'credit'
  ELSE 'sale'
END
WHERE transaction_type IS NULL;

-- Step 3: Add check constraint and NOT NULL after backfill is clean
ALTER TABLE past_bills
  ALTER COLUMN transaction_type SET NOT NULL;

ALTER TABLE past_bills
  ADD CONSTRAINT past_bills_transaction_type_check
  CHECK (transaction_type IN ('sale', 'credit', 'payment'));

-- Step 4: Index for fast filter (reports screen filters by type)
CREATE INDEX IF NOT EXISTS idx_past_bills_transaction_type
  ON past_bills(user_id, transaction_type);

-- Verify backfill
SELECT transaction_type, COUNT(*) FROM past_bills GROUP BY transaction_type;
