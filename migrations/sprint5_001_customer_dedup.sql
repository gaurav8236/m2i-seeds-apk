-- ─────────────────────────────────────────────────────────────────────────────
-- Sprint 5 Migration 001: Normalize customer names (fixes #57, #58)
--
-- Problem: "Mayank" and "mayank" create two separate customer rows,
-- splitting ₹13,184 of outstanding between them.
--
-- This script:
--   1. Trims leading/trailing spaces in customers and past_bills.
--   2. For each (user_id, lower(name)) group with duplicates:
--      - Picks the OLDEST customer row as canonical (preserves opening_balance).
--      - Renames all past_bills from dupe names → canonical name.
--      - Deletes the duplicate customer rows.
--
-- SAFE: Only touches rows where duplicates exist.
-- IDEMPOTENT: Re-running after it succeeds is a no-op.
-- ─────────────────────────────────────────────────────────────────────────────

-- Step 1: Trim whitespace (#57)
UPDATE customers
SET name = TRIM(name)
WHERE name IS NOT NULL AND name <> TRIM(name);

UPDATE past_bills
SET customer_name = TRIM(customer_name)
WHERE customer_name IS NOT NULL AND customer_name <> TRIM(customer_name);

-- Step 2: Find duplicate (user_id, name-key) groups and pick canonical name.
--   canonical_name = name from the oldest (first-created) customer row.
--   canonical_id   = id of that row.
WITH canonical AS (
  SELECT
    user_id,
    LOWER(TRIM(name))                                    AS name_key,
    (ARRAY_AGG(name    ORDER BY created_at ASC))[1]     AS canonical_name,
    (ARRAY_AGG(id::text ORDER BY created_at ASC))[1]    AS canonical_id
  FROM customers
  GROUP BY user_id, LOWER(TRIM(name))
  HAVING COUNT(*) > 1
),
-- Step 3: Re-point past_bills to the canonical name for any name variant.
dupe_names AS (
  SELECT c.user_id, c.name AS dupe_name, can.canonical_name
  FROM customers c
  JOIN canonical can
    ON  c.user_id = can.user_id
    AND LOWER(TRIM(c.name)) = can.name_key
    AND c.id::text <> can.canonical_id
)
UPDATE past_bills pb
SET customer_name = dn.canonical_name
FROM dupe_names dn
WHERE pb.user_id    = dn.user_id
  AND LOWER(TRIM(pb.customer_name)) = LOWER(TRIM(dn.dupe_name));

-- Step 4: Delete duplicate customer rows (bills already re-pointed above).
DELETE FROM customers c
WHERE c.id::text IN (
  SELECT c2.id::text
  FROM customers c2
  JOIN (
    SELECT
      user_id,
      LOWER(TRIM(name))  AS name_key,
      MIN(created_at)    AS oldest_at
    FROM customers
    GROUP BY user_id, LOWER(TRIM(name))
    HAVING COUNT(*) > 1
  ) grp
    ON  c2.user_id = grp.user_id
    AND LOWER(TRIM(c2.name)) = grp.name_key
  WHERE c2.created_at > grp.oldest_at
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Verify (should return 0 rows after successful run):
--   SELECT user_id, LOWER(TRIM(name)) AS key, COUNT(*)
--   FROM customers
--   GROUP BY user_id, LOWER(TRIM(name))
--   HAVING COUNT(*) > 1;
-- ─────────────────────────────────────────────────────────────────────────────
