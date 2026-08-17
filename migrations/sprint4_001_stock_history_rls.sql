-- ─────────────────────────────────────────────────────────────────────────────
-- Sprint 4 Migration 001: RLS for stock_history
--
-- stock_history was omitted from Sprint 3 RLS migration.
-- Flutter writes to it with the anon key (logRestock).
-- user_id column type: check before running — sprint3 showed voice_logs was text.
--
-- Verify first:
--   SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_name = 'stock_history' AND column_name = 'user_id';
--
-- If data_type = 'uuid' → use the policy below as-is.
-- If data_type = 'text' → change to: auth.uid()::text = user_id
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE stock_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_own_stock_history" ON stock_history;

CREATE POLICY "users_own_stock_history" ON stock_history
  FOR ALL
  USING  (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- Verify:
-- SELECT tablename, policyname FROM pg_policies
-- WHERE tablename = 'stock_history';
-- ─────────────────────────────────────────────────────────────────────────────
