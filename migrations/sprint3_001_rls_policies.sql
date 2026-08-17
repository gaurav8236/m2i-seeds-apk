-- ─────────────────────────────────────────────────────────────────────────────
-- Sprint 3 Migration 001: Row Level Security for user-owned tables
--
-- Run order: after all Sprint 2 migrations.
--
-- Affected tables: customers, past_bills, user_stock, voice_logs
-- Admin app and Python backend use the SERVICE ROLE KEY → RLS bypassed (safe).
-- Flutter app uses the ANON KEY → RLS enforced; user only sees their own rows.
--
-- master_inventory is a shared catalog — no user_id column, RLS not applied.
-- Only service role writes to it (via upsert_inventory_item RPC).
-- ─────────────────────────────────────────────────────────────────────────────

-- ── customers ────────────────────────────────────────────────────────────────

ALTER TABLE customers ENABLE ROW LEVEL SECURITY;

-- Drop any accidental leftover policies before creating.
DROP POLICY IF EXISTS "users_own_customers"  ON customers;

CREATE POLICY "users_own_customers" ON customers
  FOR ALL
  USING  (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ── past_bills ───────────────────────────────────────────────────────────────

ALTER TABLE past_bills ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_own_past_bills" ON past_bills;

CREATE POLICY "users_own_past_bills" ON past_bills
  FOR ALL
  USING  (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ── user_stock ───────────────────────────────────────────────────────────────

ALTER TABLE user_stock ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_own_user_stock" ON user_stock;

CREATE POLICY "users_own_user_stock" ON user_stock
  FOR ALL
  USING  (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ── voice_logs ───────────────────────────────────────────────────────────────
-- NOTE: voice_logs.user_id is TEXT (not uuid), so auth.uid() must be cast.

ALTER TABLE voice_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_own_voice_logs" ON voice_logs;

CREATE POLICY "users_own_voice_logs" ON voice_logs
  FOR ALL
  USING  (auth.uid()::text = user_id)
  WITH CHECK (auth.uid()::text = user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- Verify (run after migration):
--
-- SELECT tablename, policyname, cmd
-- FROM pg_policies
-- WHERE tablename IN ('customers','past_bills','user_stock','voice_logs')
-- ORDER BY tablename, policyname;
-- ─────────────────────────────────────────────────────────────────────────────
