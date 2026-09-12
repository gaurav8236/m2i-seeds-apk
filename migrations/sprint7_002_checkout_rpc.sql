-- ============================================================
-- Sprint 7 · Migration 002
-- checkout_and_apply_balance() — atomic checkout RPC
-- Risk: HIGH — first function body this project has checked in that's
--   explicitly invoked via .rpc() from application code (compare:
--   upsert_inventory_item is called the same way but its body was
--   never checked in anywhere — this migration fixes that pattern for
--   this function). backend/main.py's /voice-checkout/ MUST be
--   updated in the same deploy this ships with — the old Python loop
--   is removed, not kept as a fallback, so checkout breaks if this
--   migration isn't applied first.
-- Run order: SECOND in Sprint 7 (after 001 — needs running_balance /
--   last_bill_at and the sprint6_001 unique index).
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

-- Lock down who can call it — same trust boundary as today (only
-- backend/'s service-role key ever calls /voice-checkout/).
REVOKE ALL ON FUNCTION checkout_and_apply_balance(
  UUID, TEXT, TEXT, BOOLEAN, NUMERIC, NUMERIC, NUMERIC, JSONB
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION checkout_and_apply_balance(
  UUID, TEXT, TEXT, BOOLEAN, NUMERIC, NUMERIC, NUMERIC, JSONB
) TO service_role;

-- Verify
SELECT proname, pg_get_function_identity_arguments(oid)
FROM pg_proc WHERE proname = 'checkout_and_apply_balance';

SELECT grantee, privilege_type
FROM information_schema.role_routine_grants
WHERE routine_name = 'checkout_and_apply_balance';
