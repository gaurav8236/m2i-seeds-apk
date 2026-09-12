-- ============================================================
-- Sprint 7 · Migration 001
-- customers.running_balance + customers.last_bill_at
-- Risk: MEDIUM — new columns, one-time backfill scans all past_bills
-- Run order: FIRST in Sprint 7 (before 002 — the checkout RPC writes
--   to running_balance and expects it to exist and be correctly
--   backfilled).
-- Prerequisite: sprint6_001 (customers_user_id_name_lower_idx) already
--   applied — both this backfill's name-matching join and 002's RPC
--   customer lookup rely on that unique index existing.
-- ============================================================

-- PRE-CHECK: confirm no duplicate (user_id, lower(trim(name))) groups
-- exist. Must return 0 rows (sprint6_001 should already guarantee this).
SELECT user_id, LOWER(TRIM(name)) AS key, COUNT(*)
FROM customers
GROUP BY user_id, LOWER(TRIM(name))
HAVING COUNT(*) > 1;

-- ─────────────────────────────────────────────────────────────
-- Step 1: add the two new columns.
--
-- running_balance = pure bill-driven delta ONLY (credit/split/payment/
--   deposit effects) — deliberately does NOT fold in opening_balance,
--   so editing opening_balance later (updateCustomer) never needs to
--   touch this column. outstanding = opening_balance + running_balance,
--   computed by the app at read time (matches current app semantics
--   exactly — see fetchTotalOutstanding/fetchCustomers in
--   mobile/lib/services/supabase_service.dart before this migration).
--
-- last_bill_at = most recent bill of ANY type for this customer name
--   (mirrors today's client-side lastPurchaseAt, which updates on
--   every bill type, not just credit-affecting ones).
-- ─────────────────────────────────────────────────────────────
ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS running_balance NUMERIC NOT NULL DEFAULT 0;

ALTER TABLE customers
  ADD COLUMN IF NOT EXISTS last_bill_at TIMESTAMPTZ;

-- Step 2: one-time backfill — matches the exact business rules in
-- mobile/lib/services/supabase_service.dart (fetchTotalOutstanding /
-- fetchCustomers), including the pre-Sprint-3 transaction_type-NULL
-- fallback:
--   credit  → +total_amount
--   split   → +GREATEST(total_amount - nagad_amount, 0)
--   payment → -total_amount
--   deposit → -total_amount
--   sale (or NULL type + is_credit=false) → neutral (0)
WITH bill_effects AS (
  SELECT
    b.user_id,
    LOWER(TRIM(b.customer_name)) AS name_key,
    SUM(
      CASE COALESCE(b.transaction_type,
                     CASE WHEN b.is_credit THEN 'credit' ELSE 'sale' END)
        WHEN 'credit'  THEN b.total_amount
        WHEN 'split'   THEN GREATEST(b.total_amount - COALESCE(b.nagad_amount, 0), 0)
        WHEN 'payment' THEN -b.total_amount
        WHEN 'deposit' THEN -b.total_amount
        ELSE 0
      END
    ) AS delta,
    MAX(b.created_at) AS last_at
  FROM past_bills b
  WHERE b.customer_name IS NOT NULL AND TRIM(b.customer_name) <> ''
  GROUP BY b.user_id, LOWER(TRIM(b.customer_name))
)
UPDATE customers c
SET running_balance = COALESCE(be.delta, 0),
    last_bill_at     = be.last_at
FROM bill_effects be
WHERE c.user_id = be.user_id
  AND LOWER(TRIM(c.name)) = be.name_key;

-- Step 3: verify — spot-check individual customers against what the
-- CURRENT (pre-this-task) app shows for the same names in Khata,
-- before mobile is cut over to reading this column (migration 002 +
-- the app-code changes that follow it).
SELECT c.id, c.name, c.opening_balance, c.running_balance,
       c.opening_balance + c.running_balance AS computed_outstanding,
       c.last_bill_at
FROM customers c
ORDER BY c.last_bill_at DESC NULLS LAST
LIMIT 20;

-- Platform-wide sanity check: sum via the new columns (per-customer
-- clamp, matching bug #48's fix) — compare to the OLD app's dashboard/
-- reports total for a couple of real shops before relying on this.
SELECT c.user_id, SUM(GREATEST(c.opening_balance + c.running_balance, 0)) AS total_outstanding
FROM customers c
GROUP BY c.user_id;
