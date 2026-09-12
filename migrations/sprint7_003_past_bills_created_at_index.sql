-- ============================================================
-- Sprint 7 · Migration 003 (P2-b)
-- idx_past_bills_created_at — supports admin's platform-wide,
-- no-user_id, created_at-filtered scans (dashboard + shopkeeper list).
-- Risk: LOW — pure index add, CONCURRENTLY to avoid locking a table
--   that's written on every single checkout, platform-wide, at all
--   hours.
-- Run order: independent of 001/002 — safe to run any time. Should
--   run before 004 so admin_bill_aggregates() is index-backed from
--   day one.
-- ⚠️ CREATE INDEX CONCURRENTLY cannot run inside a multi-statement
--   transaction block — run the CREATE INDEX statement below by
--   itself in the SQL editor, not pasted together with other DDL in
--   one run.
-- ============================================================

-- PRE-CHECK
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'past_bills';

-- Apply (run alone)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_past_bills_created_at
  ON past_bills (created_at);

-- Verify
SELECT indexname, indexdef FROM pg_indexes
WHERE tablename = 'past_bills' AND indexname = 'idx_past_bills_created_at';
