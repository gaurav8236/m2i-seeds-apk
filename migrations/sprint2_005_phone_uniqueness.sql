-- ============================================================
-- Sprint 2 · Migration 005
-- Phone uniqueness constraint on customers (bug #40)
-- Risk: MEDIUM — will fail if duplicate phones exist
-- Run order: FIFTH (last, independent of 003/004)
-- ⚠️  Run pre-check first. Resolve duplicates, then add constraint.
-- ============================================================

-- PRE-CHECK: find duplicate phone numbers per user
SELECT user_id, phone, COUNT(*) AS duplicates
FROM customers
WHERE phone IS NOT NULL AND phone != ''
GROUP BY user_id, phone
HAVING COUNT(*) > 1
ORDER BY duplicates DESC;

-- If duplicates exist, review them:
SELECT id, name, phone, created_at
FROM customers
WHERE phone IN (
  SELECT phone FROM customers
  WHERE phone IS NOT NULL
  GROUP BY user_id, phone
  HAVING COUNT(*) > 1
)
ORDER BY phone, created_at;

-- ─────────────────────────────────────────────────────────────
-- Resolution options for duplicates (pick one per pair):
--   A) Keep newer, nullify older phone:
--      UPDATE customers SET phone = NULL WHERE id = '<older_id>';
--   B) Merge: move all bills from one customer to another,
--      then delete the duplicate row.
-- Sprint 2 constraint is partial — NULL phones are excluded
-- so anonymous customers (no phone) don't block the constraint.
-- ─────────────────────────────────────────────────────────────

-- Add partial unique index (NULLs are excluded from uniqueness check)
-- Scoped per user_id so two different shops can have the same customer phone
CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_user_phone_unique
  ON customers(user_id, phone)
  WHERE phone IS NOT NULL AND phone != '';

-- Verify
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'customers' AND indexname = 'idx_customers_user_phone_unique';
