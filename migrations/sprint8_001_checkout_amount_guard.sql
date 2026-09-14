-- ============================================================
-- Sprint 8 · Migration 001
-- checkout_and_apply_balance() — reject non-sensical money values
-- (P1 money-safety fix)
--
-- Why a new "sprint8" prefix instead of continuing sprint7_00N:
--   sprint7_001..005 were all one batch, applied together, for one
--   dated piece of work (the P2 performance fixes / D3 decision —
--   running_balance, this same RPC, the created_at index, the admin
--   aggregate RPC, and the transaction_type CHECK widen). That batch
--   is closed out and already live. This fix is a separate, later,
--   unrelated task (a P1 money-correctness gap found during the
--   2026-09-13 customer-ledger design review, tracked in
--   .claude/TODOS.md under Backend and filed as BUG-14 in
--   .claude/qa/BUGS.md) — same pattern as sprint3..sprint6 each
--   getting their own top-level sprint number for a single unrelated
--   change, rather than being folded into a closed batch's numbering.
--   Starting a new sprint8 series here rather than sprint7_006.
--
-- What this does:
--   CREATE OR REPLACE FUNCTION checkout_and_apply_balance() with the
--   EXACT SAME signature and full existing body from
--   sprint7_002_checkout_rpc.sql, plus one new guard clause inserted
--   at the very top of the function body — before Phase 1's oversell
--   check, before any reads/locks, before any writes. Nothing else in
--   the function changes.
--
-- The guard rejects (does NOT clamp/silently correct):
--   - p_total_amount < 0
--   - p_discount_amount < 0
--   - p_nagad_amount < 0
--   - p_nagad_amount > p_total_amount   (a split's cash portion can't
--     exceed the bill total)
-- by returning jsonb_build_object('status', 'invalid', 'message', ...)
-- before touching user_stock, past_bills, or customers — analogous in
-- shape to Phase 1's existing 'partial' (oversold) rejection, but a
-- distinct 'status' value so backend/mobile can tell "bad money
-- values" apart from "not enough stock" if they ever need to branch
-- on it.
--
-- Known gap NOT covered by this guard (flagging explicitly, not
-- silently expanding scope beyond what was asked): a NULL
-- p_total_amount/p_discount_amount/p_nagad_amount passes this guard
-- untouched, because `NULL < 0` evaluates to NULL, not TRUE, in
-- Postgres — it does not fail the IF condition. There is also no
-- NOT NULL / CHECK constraint on past_bills' money columns today (see
-- sprint2_004_db_constraints.sql — it only constrains
-- user_stock/selling_price). A NULL total_amount would currently
-- insert as NULL into past_bills and contribute NULL (a no-op, per
-- Postgres arithmetic) to the running_balance delta in Phase 4 — not
-- the same silent-debt-reduction bug this migration closes, but still
-- an unvalidated input. Not in scope for this migration (only the 4
-- conditions above were requested); flagged here for whoever picks up
-- the next pass on this RPC.
--
-- RLS: not applicable — this function is SECURITY INVOKER, called only
-- by backend/'s service-role Supabase connection (which bypasses RLS
-- entirely), same as sprint7_002. No RLS policy touches this path.
--
-- Grants: CREATE OR REPLACE FUNCTION in Postgres preserves the
-- existing ownership and ACL (GRANT/REVOKE) state of a function,
-- provided the signature (name + argument types) is unchanged, and
-- this migration keeps the signature byte-for-byte identical to
-- sprint7_002. That preservation behavior is unchanged and documented
-- across all currently-supported Postgres major versions used by
-- Supabase (see "Notes" on CREATE FUNCTION in the Postgres docs) — it
-- is not new or version-fragile. That said: this project already hit
-- a real grants-related outage once (BUG-1/BUG-2 — Supabase's
-- project-level `ALTER DEFAULT PRIVILEGES` grants EXECUTE directly to
-- named roles, not via PUBLIC, making a plain `REVOKE ALL FROM PUBLIC`
-- a no-op by construction on this project). Because that has already
-- bitten this exact function once, this migration restates the same
-- corrected REVOKE/GRANT block below defensively, and re-runs the same
-- verification queries sprint7_002/BUG-2's fix used — treat the
-- verify query's actual output as the source of truth, not this
-- comment.
--
-- Run order: after sprint7_001..005 (this function must already exist
-- with the running_balance-aware body from sprint7_002 for this
-- CREATE OR REPLACE to be "add a guard", not "recreate from scratch").
-- Independent of sprint8 having any other files (none exist yet).
-- NOT YET APPLIED to the live Supabase project as of writing — needs
-- explicit user go-ahead immediately before running, per this
-- project's standing rule on live migrations.
-- ============================================================

CREATE OR REPLACE FUNCTION checkout_and_apply_balance(
  p_user_id          UUID,
  p_customer_name    TEXT,
  p_transaction_type TEXT,
  p_is_credit        BOOLEAN,
  p_total_amount     NUMERIC,
  p_discount_amount  NUMERIC,
  p_nagad_amount     NUMERIC,
  p_items            JSONB
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER  -- caller is always backend's service-role connection;
                   -- no privilege elevation needed/wanted here
AS $$
DECLARE
  v_item          JSONB;
  v_stock_id      UUID;
  v_new_stock     NUMERIC;
  v_db_stock      NUMERIC;
  v_qty_deducted  NUMERIC;
  v_oversold      JSONB := '[]'::jsonb;
  v_delta         NUMERIC := 0;
  v_bill_id       UUID;
BEGIN
  -- Phase 0 — money-safety guard (sprint8_001, BUG-14). Runs before
  -- Phase 1 and before any reads/locks/writes. Rejects, never clamps:
  -- a negative total/discount/nagad amount, or a nagad (cash) amount
  -- that exceeds the bill total, can never be legitimate input from
  -- either the voice-checkout flow or manual billing — letting one
  -- through here is what previously let a negative p_total_amount on
  -- a credit/split checkout apply as a negative delta to
  -- customers.running_balance with no bill, no payment, no trace.
  IF p_total_amount < 0
     OR p_discount_amount < 0
     OR p_nagad_amount < 0
     OR p_nagad_amount > p_total_amount THEN
    RETURN jsonb_build_object(
      'status', 'invalid',
      'message', 'बिल की राशि गलत है — जांच कर दोबारा कोशिश करें'
    );
  END IF;

  -- Phase 1 — validate ALL items first. No writes yet: if anything is
  -- oversold we return here with zero side effects — this is what
  -- makes the whole bill atomic ("all or nothing"), not just "faster".
  -- SELECT ... FOR UPDATE locks each row so a concurrent checkout on
  -- the same stock_id can't interleave between validation and Phase 2.
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    BEGIN
      v_stock_id := NULLIF(v_item->>'stock_id', '')::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
      v_stock_id := NULL;  -- malformed id → falls into "not found" below
    END;
    v_new_stock := NULLIF(v_item->>'new_stock', '')::numeric;

    IF v_stock_id IS NOT NULL AND v_new_stock IS NOT NULL THEN
      SELECT current_stock INTO v_db_stock
      FROM user_stock
      WHERE id = v_stock_id AND user_id = p_user_id
      FOR UPDATE;

      IF NOT FOUND THEN
        v_oversold := v_oversold || jsonb_build_object(
          'item_name', v_item->>'item_name',
          'requested', COALESCE((v_item->>'quantity_billed')::numeric, 0),
          'available', 0
        );
        CONTINUE;
      END IF;

      v_qty_deducted := ROUND(v_db_stock - v_new_stock, 1);
      IF v_qty_deducted > v_db_stock THEN
        v_oversold := v_oversold || jsonb_build_object(
          'item_name', v_item->>'item_name',
          'requested', v_qty_deducted,
          'available', v_db_stock
        );
      END IF;
    END IF;
  END LOOP;

  IF jsonb_array_length(v_oversold) > 0 THEN
    RETURN jsonb_build_object(
      'status', 'partial',
      'message', 'कुछ सामान का स्टॉक पर्याप्त नहीं था — बिल सहेजा नहीं गया',
      'oversold', v_oversold
    );
  END IF;

  -- Phase 2 — apply stock deductions (same locked rows from Phase 1,
  -- same transaction — lock never released between phases).
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_stock_id := NULLIF(v_item->>'stock_id', '')::uuid;
    v_new_stock := NULLIF(v_item->>'new_stock', '')::numeric;
    IF v_stock_id IS NOT NULL AND v_new_stock IS NOT NULL THEN
      UPDATE user_stock
      SET current_stock = GREATEST(0, ROUND(v_new_stock, 1))
      WHERE id = v_stock_id AND user_id = p_user_id;
    END IF;
  END LOOP;

  -- Phase 3 — insert the bill row (bill_details = same item array
  -- shape the old Python loop stored — unchanged, so
  -- fetchItemSalesThisMonth's bill_details scans keep working).
  INSERT INTO past_bills (
    user_id, total_amount, discount_amount, customer_name,
    is_credit, transaction_type, nagad_amount, bill_details
  ) VALUES (
    p_user_id, p_total_amount, p_discount_amount, p_customer_name,
    p_is_credit, p_transaction_type, p_nagad_amount, p_items
  )
  RETURNING id INTO v_bill_id;

  -- Phase 4 — best-effort running-balance + last-activity update,
  -- matched by name exactly like every other lookup in this codebase
  -- (ensureCustomerExists, fetchCustomerLedger) — no customer_id
  -- dependency. A non-matching name is a silent no-op (mirrors
  -- ensureCustomerExists's own non-fatal handling) rather than failing
  -- the whole checkout.
  IF p_customer_name IS NOT NULL AND length(trim(p_customer_name)) > 0 THEN
    v_delta := CASE p_transaction_type
      WHEN 'credit'  THEN p_total_amount
      WHEN 'split'   THEN GREATEST(p_total_amount - COALESCE(p_nagad_amount, 0), 0)
      WHEN 'payment' THEN -p_total_amount
      WHEN 'deposit' THEN -p_total_amount
      ELSE 0
    END;

    UPDATE customers
    SET running_balance = running_balance + v_delta,
        last_bill_at    = now()
    WHERE id = (
      SELECT id FROM customers
      WHERE user_id = p_user_id
        AND LOWER(TRIM(name)) = LOWER(TRIM(p_customer_name))
      LIMIT 1
    );
  END IF;

  RETURN jsonb_build_object(
    'status', 'success',
    'message', 'Stock updated and bill saved successfully',
    'bill_id', v_bill_id
  );
END;
$$;

-- Restate the lockdown defensively (see "Grants" note above — this
-- project has already hit a real outage from assuming a grant carried
-- over correctly; BUG-1/BUG-2). Same trust boundary as sprint7_002:
-- only backend/'s service-role key ever calls /voice-checkout/.
REVOKE ALL ON FUNCTION checkout_and_apply_balance(
  UUID, TEXT, TEXT, BOOLEAN, NUMERIC, NUMERIC, NUMERIC, JSONB
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION checkout_and_apply_balance(
  UUID, TEXT, TEXT, BOOLEAN, NUMERIC, NUMERIC, NUMERIC, JSONB
) TO service_role;

-- Verify signature unchanged
SELECT proname, pg_get_function_identity_arguments(oid)
FROM pg_proc WHERE proname = 'checkout_and_apply_balance';

-- Verify grants: expect only service_role/postgres (owner), same as
-- BUG-2's fixed state — if anon/authenticated show up here, the
-- lockdown did not carry over and needs the same fix as BUG-1/BUG-2.
SELECT grantee, privilege_type
FROM information_schema.role_routine_grants
WHERE routine_name = 'checkout_and_apply_balance';

-- Manual smoke tests to run after applying (SQL editor, throwaway
-- p_user_id/customer — do not run against a real shop's data):
--   1. p_total_amount = -100, p_transaction_type = 'credit'
--      → expect {"status": "invalid", ...}, running_balance unchanged.
--   2. p_discount_amount = -1 → expect {"status": "invalid", ...}.
--   3. p_nagad_amount = -1 → expect {"status": "invalid", ...}.
--   4. p_total_amount = 100, p_nagad_amount = 150, p_transaction_type
--      = 'split' → expect {"status": "invalid", ...}.
--   5. A normal valid credit/split/sale/payment/deposit call still
--      returns {"status": "success", ...} exactly as before (no
--      regression on the happy path).
