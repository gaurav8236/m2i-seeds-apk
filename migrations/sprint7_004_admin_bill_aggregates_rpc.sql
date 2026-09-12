-- ============================================================
-- Sprint 7 · Migration 004 (P2-b)
-- admin_bill_aggregates() — per-shop bill count/GMV/last-activity for
-- a date range, computed in SQL instead of admin/ fetching every
-- matching past_bills row and reducing in JavaScript.
-- Risk: LOW — read-only aggregate, no schema/data changes.
-- Run order: after 003 (created_at index) so this is index-scan
--   backed from day one, not a sequential scan.
-- ============================================================

CREATE OR REPLACE FUNCTION admin_bill_aggregates(
  p_from TIMESTAMPTZ,
  p_to   TIMESTAMPTZ DEFAULT NULL
) RETURNS TABLE (
  user_id      UUID,
  shop_name    VARCHAR,
  display_name VARCHAR,
  email        TEXT,
  bill_count   BIGINT,
  gmv          NUMERIC,
  last_bill_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    pb.user_id, u.shop_name, u.display_name, u.email,
    COUNT(*)                          AS bill_count,
    COALESCE(SUM(pb.total_amount), 0) AS gmv,
    MAX(pb.created_at)                AS last_bill_at
  FROM past_bills pb
  JOIN users u ON u.id = pb.user_id
  WHERE pb.created_at >= p_from
    AND (p_to IS NULL OR pb.created_at < p_to)
  GROUP BY pb.user_id, u.shop_name, u.display_name, u.email;
$$;

REVOKE ALL ON FUNCTION admin_bill_aggregates(TIMESTAMPTZ, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_bill_aggregates(TIMESTAMPTZ, TIMESTAMPTZ) TO service_role;

-- Verify — one row per shop that billed today, not one row per bill
SELECT * FROM admin_bill_aggregates(date_trunc('day', now()), NULL) LIMIT 20;
