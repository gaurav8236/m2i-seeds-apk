-- ============================================================
-- Sprint 2 · Migration 003
-- customer_id FK on past_bills (bugs #52, #42)
-- Risk: HIGH — requires matching all bill customer_name → customers.id
-- Run order: THIRD (after 002)
-- ⚠️  Run the pre-check query first. Fix any unmatched names before Step 3.
-- ============================================================

-- PRE-CHECK: find bill customer_names with no matching customer row
-- Run this first, fix unmatched rows manually, then proceed.
SELECT DISTINCT b.customer_name
FROM past_bills b
LEFT JOIN customers c
  ON LOWER(TRIM(b.customer_name)) = LOWER(TRIM(c.name))
  AND b.user_id = c.user_id
WHERE b.customer_name IS NOT NULL
  AND c.id IS NULL
ORDER BY b.customer_name;

-- ─────────────────────────────────────────────────────────────
-- Only run Steps 1-4 after the pre-check returns 0 rows
-- ─────────────────────────────────────────────────────────────

-- Step 1: Add the FK column as nullable
ALTER TABLE past_bills
  ADD COLUMN IF NOT EXISTS customer_id UUID REFERENCES customers(id) ON DELETE SET NULL;

-- Step 2: Backfill — match on lowercased + trimmed name, same user_id
UPDATE past_bills b
SET customer_id = c.id
FROM customers c
WHERE LOWER(TRIM(b.customer_name)) = LOWER(TRIM(c.name))
  AND b.user_id = c.user_id
  AND b.customer_id IS NULL;

-- Step 3: Verify backfill coverage
-- Bills with a customer_name but no customer_id after backfill = data gap
SELECT COUNT(*) AS unlinked_bills
FROM past_bills
WHERE customer_name IS NOT NULL AND customer_id IS NULL;

-- Step 4: Index for joins (customer ledger queries)
CREATE INDEX IF NOT EXISTS idx_past_bills_customer_id
  ON past_bills(user_id, customer_id);

-- NOTE: Do NOT add NOT NULL on customer_id yet — anonymous cash sales have
-- no customer. Keep it nullable. Only credit bills should always have customer_id.
-- That validation stays in Flutter (review screen), not a DB constraint.
