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
