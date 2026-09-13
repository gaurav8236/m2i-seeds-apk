-- ============================================================
-- Sprint 7 · Migration 005
-- Widen past_bills_transaction_type_check to match what the app writes
-- Risk: LOW — pure CHECK-constraint widen, no data change, no rewrite.
-- Run order: independent of 001-004, safe to run any time. Should be
--   applied before/alongside pushing backend's live-code change (which
--   is already able to write 'split'/'deposit', but has been unable to
--   because the DB rejects it — see evidence below).
-- ============================================================

-- Context: sprint2_002_transaction_type.sql (Sprint 2) constrained this
-- column to ('sale', 'credit', 'payment') only. backend/main.py has
-- derived 'split' (is_credit=true + nagad_amount>0, i.e. a part-cash/
-- part-credit bill) since before Sprint 7, and separately writes
-- 'deposit' for recordDeposit() — mobile/lib/services/supabase_service.dart
-- also defensively excludes a 'cash_loan' value from a query filter
-- (line ~269) though nothing currently writes that one. Flagged as a
-- known issue in docs/DATABASE.md and .claude/TODOS.md ("Database /
-- schema") from the architecture pass, but not yet actioned — now
-- confirmed as a **live production bug**, not just a doc/code mismatch:
-- a real manual-billing user hit "Checkout failed: 500" every time both
-- "उधार पर?" and "कुछ नकद भी दिया?" were toggled on together (a split
-- bill), reproduced live via `INSERT ... transaction_type='split'` ->
-- `23514 past_bills_transaction_type_check` violation (service-role,
-- rolled back — see .claude/qa/BUGS.md BUG-4). Every historical bill
-- confirms this: `SELECT DISTINCT transaction_type FROM past_bills`
-- has only ever returned sale/credit/payment — split and deposit bills
-- have never once been able to save, in the app's entire history.

-- PRE-CHECK: confirm current constraint definition (should show only
-- sale/credit/payment) and confirm no existing rows would violate the
-- widened version (they can't, this only adds allowed values).
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conname = 'past_bills_transaction_type_check';

-- Apply: drop and recreate with the full set the app actually writes.
ALTER TABLE past_bills
  DROP CONSTRAINT past_bills_transaction_type_check;

ALTER TABLE past_bills
  ADD CONSTRAINT past_bills_transaction_type_check
  CHECK (transaction_type IN ('sale', 'credit', 'payment', 'split', 'deposit'));

-- Verify
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conname = 'past_bills_transaction_type_check';

-- Sanity re-check (safe, rolled back): confirm 'split' now inserts past
-- the CHECK (will still fail on the FK for this bogus user_id, which is
-- expected and fine — the point is confirming it's no longer 23514):
-- INSERT INTO past_bills (user_id, total_amount, transaction_type, is_credit, nagad_amount, customer_name, bill_details)
-- VALUES ('00000000-0000-0000-0000-000000000000', 1, 'split', true, 1, 'x', '[]');
