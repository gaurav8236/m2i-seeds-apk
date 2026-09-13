# Sprint 2 — DB Migrations

Run these in order in the **Supabase SQL Editor** (Dashboard → SQL Editor).  
Each file has pre-check queries — **run them first**, fix violations, then apply the migration.

## Run order

| # | File | Risk | Prerequisite |
|---|---|---|---|
| 001 | `sprint2_001_cascade_delete.sql` | 🟢 Low | None — run anytime |
| 002 | `sprint2_002_transaction_type.sql` | 🟡 Medium | None — backfill is self-contained |
| 003 | `sprint2_003_customer_id_fk.sql` | 🔴 High | Pre-check must return 0 unmatched names |
| 004 | `sprint2_004_db_constraints.sql` | 🔴 High | Fix 5 decimal stock rows first (included in file) |
| 005 | `sprint2_005_phone_uniqueness.sql` | 🟡 Medium | Pre-check for duplicate phones |

## Safe to run now (Sprint 2 start)
- **001** — just a FK constraint change, zero data risk
- **002** — adds a column + backfills; self-contained

## Needs data review before running
- **003** — run the pre-check SELECT first; every unmatched `customer_name` needs a `customers` row
- **004** — the fix UPDATEs are included but verify the 5 decimal rows are what you expect before committing
- **005** — run the duplicate phone pre-check; resolve any duplicates manually

## After all migrations
Flutter code changes for Sprint 2 will use `customer_id` instead of `customer_name` for joins,
and `transaction_type` instead of `is_credit` for filtering. Those Flutter changes come after
the schema is stable on staging.

(Note: this README was never updated for Sprints 3–6, which also exist in this folder —
`sprint3_001_rls_policies.sql`, `sprint4_001_stock_history_rls.sql`,
`sprint5_001_customer_dedup.sql`, `sprint6_001_customer_unique_name.sql`. Each of those files'
own header comments document its own run order/risk/prerequisites; not backfilling a table for
them here to keep this change scoped to Sprint 7.)

---

# Sprint 7 — Performance fixes (P2-a/b/c)

Diagnosed in `.claude/records/2026-09-13-performance-diagnosis.md`, designed per
`.claude/records/DECISIONS.md` D3. Run these against the live Supabase project **before**
deploying `backend/main.py`'s corresponding change or the mobile/admin app-code changes that
read the new column/RPCs — all three depend on this schema existing first.

## Run order

| # | File | Risk | Prerequisite |
|---|---|---|---|
| 001 | `sprint7_001_customer_running_balance.sql` | 🟡 Medium | `sprint6_001` applied (unique name index) |
| 002 | `sprint7_002_checkout_rpc.sql` | 🔴 High | 001 applied — writes to `running_balance`/`last_bill_at` |
| 003 | `sprint7_003_past_bills_created_at_index.sql` | 🟢 Low | None — independent of 001/002. **Run this one alone** — `CREATE INDEX CONCURRENTLY` cannot be inside a multi-statement transaction block with anything else. |
| 004 | `sprint7_004_admin_bill_aggregates_rpc.sql` | 🟢 Low | 003 applied (so the aggregate query is index-backed from the start) |
| 005 | `sprint7_005_widen_transaction_type_check.sql` | 🟢 Low | None — independent of 001-004. Fixes a **live bug** (BUG-4): split/deposit bills have never been able to save. |

## Safe to run now
- **003** — pure index add, zero data/behavior risk, run anytime.
- **004** — read-only aggregate function, zero data risk. Run after 003.
- **005** — widens a CHECK constraint only, no data rewrite, run anytime. Should land before/with the `backend/` push since it unblocks split/deposit bills that code already tries to write.

## Needs care
- **001** — run the pre-check first (0 duplicate-name groups expected — should already hold from
  `sprint6_001`); after applying, spot-check the verify queries' output against what the
  *current, pre-migration* app shows for a few real customers in Khata before trusting the
  backfilled numbers.
- **002** — this is the first Postgres function in this project explicitly called via `.rpc()`
  from application code with its SQL body checked in (`upsert_inventory_item` is called the same
  way but its body was never checked in anywhere — this is the first one done properly). Read it
  line-by-line against the `backend/main.py` logic it replaces before applying. **`backend/`'s
  `/voice-checkout/` deploy must ship in the same window as this migration** — the old Python
  per-item loop is being removed, not kept as a fallback, so checkout breaks if this migration
  isn't live first.

## After all migrations
Deploy `backend/main.py` (now calls `checkout_and_apply_balance` instead of looping per item),
then the `mobile/` changes (`fetchTotalOutstanding`/`fetchCustomers` now read `running_balance`
directly instead of walking bill history) and `admin/` changes (`dashboard`/`users` pages now
call `admin_bill_aggregates` instead of aggregating in JS) — see
`.claude/records/DECISIONS.md` D3 and the plan file for the full sequencing.
