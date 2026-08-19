-- ─────────────────────────────────────────────────────────────────────────────
-- Sprint 6 Migration 001: DB constraint — unique customer name per user (#42)
--
-- Prevents creating two customers with the same name (case-insensitive) for
-- the same user at the DB level, enforcing what the Sprint 5 dedup migration
-- already cleaned up.
--
-- PREREQUISITE: sprint5_001_customer_dedup.sql must have been run first so
-- there are no existing duplicates (the index creation would fail otherwise).
--
-- SAFE: IF NOT EXISTS — idempotent, re-running is a no-op.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE UNIQUE INDEX IF NOT EXISTS customers_user_id_name_lower_idx
ON customers (user_id, LOWER(TRIM(name)));

-- ─────────────────────────────────────────────────────────────────────────────
-- Verify:
--   SELECT indexname FROM pg_indexes
--   WHERE tablename = 'customers'
--   AND indexname = 'customers_user_id_name_lower_idx';
-- ─────────────────────────────────────────────────────────────────────────────
