# SmartDukan — Business Rules, Data Schema & Architecture Plan

> **Version:** Final (post-audit)  
> **Date:** 2026-08-17  
> **Status:** Agreed — implementation reference for all sprints  
> This document supersedes all earlier drafts (v1, v2, combo-box UX doc).  
> Changes from earlier drafts are noted inline where relevant.

---

## 1. PDF Architecture

### Rule — One function, one format, always

`buildBillPdfBytes()` in `lib/utils/bill_pdf.dart` is the single source of truth.  
Any screen that generates a PDF calls this function — never write PDF layout code inline elsewhere.

**The actual bug:** `shopName` is never passed in from any caller → falls back to "आपकी दुकान".

**Fix plan:**
```
App startup → fetch user profile → store in global state / Provider
     ↓
Any PDF call → read shopName from global state → pass to buildBillPdfBytes()
```

No screen fetches shop name at PDF-generation time. It is already in memory from startup.

---

## 2. Timezone — India (IST) Everywhere

### Rule — All times are IST (UTC+5:30). Always. No exceptions.

**Current bug:** `DateTime.now().toIso8601String()` sends local device time without timezone
marker → Supabase stores it as UTC → 5h 30m wrong on all queries and displays.

**Fix:**

| Where | Change |
|---|---|
| All date filters in `supabase_service.dart` (lines 116, 134–135, 347–354) | `.toUtc().toIso8601String()` |
| `auth_service.dart` user creation (line 44) | `.toUtc().toIso8601String()` |
| All display (bill card, PDF, reports) | Parse DB timestamp → `toLocal()` → format via shared helper |

**Shared display helper (to create):**
```dart
// lib/utils/date_utils.dart
String fmtDateIST(DateTime utcTime) {
  final ist = utcTime.toLocal(); // device is IST → toLocal() = IST
  return DateFormat('d MMM yyyy, h:mm a').format(ist);
}
```
Every screen uses this one function. Never call `.format()` on a raw DateTime directly.

---

## 3. Admin Panel — Data Refresh Strategy

### Decision — No realtime needed

Admin is an operations tool, not a live dashboard. Reload on page visit is sufficient.

**Current state:** all 6 admin data pages already have `export const dynamic = 'force-dynamic'`
and `export const fetchCache = 'force-no-store'`. ✅ Done. No further changes needed here.

**Rule going forward:** never add `export const revalidate = N` to admin pages. Never cache
admin data at the component level.

---

## 4. Customer Identity & Schema

### 4.1 Core design decision — names are NOT unique identifiers

In a real kirana shop, multiple customers can share the same name. "Ramesh" might be
three different people. Forcing name uniqueness is wrong — it creates friction for real
data and doesn't reflect how shopkeepers think.

**Identifiers used (in order of reliability):**
1. `phone` — most reliable, but optional
2. `tag` — short shopkeeper-set label ("colony wale", "supplier ka bhai")
3. `customer_no` — auto-assigned sequential number, never reused, always shown as fallback

### 4.2 Customer combo box — the single UX pattern

One reusable **customer combo box component** — a searchable dropdown that also accepts
free text — used in exactly **two places**:

1. **Customer management** (Add Customer entry on Khata screen)
2. **Billing settlement screen** (customer field)

**Why one component:** a shopkeeper who learns the behavior once in billing already knows
how it works in Khata. One interaction pattern everywhere, no mode-switching.

**Behavior:**

As the shopkeeper types, the dropdown live-filters and shows matching active customers.
Each row shows enough to tell people apart:

```
Has phone    →  Name  ·  tag (if set)  ·  last 4 digits of phone
No phone     →  Name  ·  tag (if set)  ·  #customer_no
```

If shopkeeper **taps an existing row:**
- In customer management → opens that customer's existing edit/detail screen, pre-filled.
  Does NOT create a new customer. Selecting = "I want this one."
- In billing → that customer is attached to the bill.

If shopkeeper **types a name and does not select any row:**
- In customer management → proceeds to create-new-customer form, pre-filled with typed name.
- In billing → on settlement, a new customer record is created with the typed name (same
  as today's create-on-the-fly behavior).

**Critical rule — always explicit tap, no auto-fill:**
The combo box **always requires an explicit tap to select**, regardless of how many matches
exist — one match or five. No auto-select code path.

> **Why:** auto-selecting among ambiguous customers risks crediting the wrong person's
> udhaar. One extra tap for a single obvious match is a deliberate trade of speed for
> correctness. The code is simpler too — no conditional branching based on match count.

**Tag field:** always visible on the create/edit customer form. Not conditional on detecting
a name collision. Shopkeeper fills it in whenever useful — low friction, always there.

### 4.3 Proposed Schema Changes

```sql
-- ── CUSTOMERS ──────────────────────────────────────────────────────────────

-- Normalized name for search only (NOT for uniqueness)
ALTER TABLE customers
  ADD COLUMN name_normalized TEXT GENERATED ALWAYS AS (lower(trim(name))) STORED;

-- Auto-increment customer number per shopkeeper — never reused
ALTER TABLE customers
  ADD COLUMN customer_no SERIAL;
-- (scoped per user_id: implement as a sequence-per-user or a
--  BEFORE INSERT trigger that sets customer_no = next count for this user_id)

-- Optional short disambiguation tag
ALTER TABLE customers
  ADD COLUMN tag TEXT; -- max 30 chars, nullable

-- Soft delete
ALTER TABLE customers
  ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT true;

-- Phone: unique per shopkeeper, max 10 digits, nullable
ALTER TABLE customers
  ADD CONSTRAINT customers_phone_unique_per_user UNIQUE (user_id, phone);

ALTER TABLE customers
  ADD CONSTRAINT customers_phone_length
  CHECK (phone IS NULL OR (phone ~ '^[0-9]{10}$'));

-- Opening balance: allow negative (customer may start with pre-existing credit)
ALTER TABLE customers
  ADD CONSTRAINT customers_opening_balance_check
  CHECK (opening_balance >= -99999);

-- ❌ NOT added: name uniqueness constraint — intentionally dropped.
--    Duplicate names per shopkeeper are real-world expected behavior.

-- ── PAST_BILLS ─────────────────────────────────────────────────────────────

-- Link bills to customer by ID (not name)
ALTER TABLE past_bills
  ADD COLUMN customer_id UUID REFERENCES customers(id) ON DELETE SET NULL;
-- Keep customer_name as a snapshot — never rewrite it retroactively.
-- customer_id is for lookups; customer_name is what was on the bill at time of sale.

-- Distinguish sales from payment receipts
ALTER TABLE past_bills
  ADD COLUMN transaction_type TEXT NOT NULL DEFAULT 'sale'
  CHECK (transaction_type IN ('sale', 'payment'));

-- ⚠️ BACKFILL WARNING: do NOT backfill transaction_type via text pattern matching
-- on bill_details JSON. See Section 9 — Data Audit Process.
```

### 4.4 Renaming a customer

Update `customers.name` only. `past_bills.customer_id` is untouched. The `customer_name`
snapshot on old bills stays as it was at time of sale — never rewritten.

### 4.5 Customer deactivation policy

- **Hard delete:** never available in UI.
- **Soft delete (deactivate):** allowed only if `outstanding_balance = 0`.
  - If balance ≠ 0: button disabled, tooltip: "Clear outstanding of ₹X before deactivating."
- **Deactivated customers:** move to a separate filtered list. Can be reactivated.
  Never mixed with active customers in any dropdown or list.

---

## 5. Business Rules

### 5.1 Billing Rules

| Rule | Detail |
|---|---|
| Bill amount ≥ ₹0 | A bill cannot be for negative money |
| Discount ≥ ₹0 | No negative discounts. Discount is a reduction only |
| Discount < subtotal | Discount cannot equal or exceed the bill subtotal. Grand total must be > ₹0 |
| Stock deduction ≤ available stock | Cannot bill more than what's in stock. Enforce on backend too |
| Bill must have at least 1 item | Empty bill cannot be created |
| Cash or Udhar — not both | One bill = one payment type. Part-cash-part-credit = two transactions |
| Discount resets when cart changes | Discount tied to the full cart — clears if items added or removed |
| Bill is immutable after creation | Past bills cannot be edited. New transactions correct mistakes |
| Void/reversal flow | Intentionally deferred. Two-step confirmation in billing flow is sufficient for now |

### 5.2 Customer / Khata Rules

| Rule | Detail |
|---|---|
| Customer name is required, min 1 char, max 60 | Cannot be blank or whitespace only |
| Duplicate names are allowed | "Ramesh" can exist multiple times — use phone/tag/#no to distinguish |
| `customer_no` is system-assigned, unique per shopkeeper, never reused | Not something shopkeeper memorises — shown as fallback in UI |
| Tag is optional, max 30 chars | Set it to distinguish people with the same name |
| Phone: exactly 10 digits, numeric only | No `+91`, no spaces, no alphabets |
| Phone is unique per shopkeeper (when provided) | Two customers cannot share the same phone |
| Opening balance ≥ -₹99,999 | Negative allowed — represents pre-existing customer credit |
| Billing combo box always requires explicit tap | No auto-select, even on a single match |
| Deactivation only when balance = 0 | See Section 4.5 |
| Rename does not affect bill history | History linked by `customer_id` |

### 5.3 Sales vs Customer Ledger — Two Separate Concerns

> These two are fundamentally different and must never be mixed.

**Sales / Revenue** — "How much did I sell today/this month?"
- Source: `past_bills WHERE transaction_type = 'sale'`
- Includes: all sale bills (Naqad + Udhar)
- Excludes: payment receipts
- Used in: Reports screen, Dashboard stats

**Customer Ledger (Khata)** — "How much does this customer owe me?"
- Formula: `opening_balance + Σ(sale bills) - Σ(payment receipts)`
- Reads both transaction types for the same customer
- Used in: Khata screen, customer detail, कुल बकाया

```
Total Sales ≠ Total Outstanding
Sales = all bills.
Outstanding = unpaid Udhar minus payments received (can go negative).
```

### 5.4 Payment / Udhar Recovery Rules

| Rule | Detail |
|---|---|
| Payment amount > ₹0 | Cannot record ₹0 or negative payment |
| No cap on payment amount | Overpayment is allowed — see 5.4a below |
| `transaction_type = 'payment'` | Not counted in billing count or sales total |
| No item entry in bill_details | Payment records have no line items |
| Reduces customer outstanding | `outstanding = opening_balance + Σsales - Σpayments` |

### 5.4a — Advance / Overpayment

A shopkeeper can record a payment larger than a customer's current outstanding. The excess
becomes a credit the customer draws down against future purchases — common with regulars
who pay ahead.

**Data:**
- Outstanding is now permitted to go negative (= shop owes the customer).
- New sale for that customer draws down the negative balance first.

**Display:**
- Khata screen: negative balance shown in green as "आपके पास जमा ₹X" (not red "बकाया")
- Dashboard: **two separate figures** — "total outstanding" and "total customer credit"
  Never netted into one number (netting understates real outstanding risk)

**Status:** scoped and ready. Treat as its own sprint — don't fold into the ledger
redesign sprint, or scope creep will stall both.

### 5.5 Inventory Rules

| Rule | Detail |
|---|---|
| Item name: min 3, max 50 chars | Required |
| Item name: letters, numbers, spaces, hyphens, `&`, `()` allowed | See audit note below |
| Selling price: ₹0 to < ₹49,999 | No negative. Decimal allowed |
| Stock: 0 to 1,00,000 | Whole numbers only |
| Low stock limit: 1 to 9,99,999 | Whole numbers only |
| Aliases (bolne ka naam): max 10 per item, each max 50 chars | Unique per item |
| Editing item name: updates existing item by ID | Edit flow must use item ID, not name |
| Deleting an item: retain snapshot in bill_details | Never cascade-delete bill data |

> **Audit finding — item name chars:** 25 real items in the DB use `&` and `()` 
> (e.g. "Head & Shoulders Shampoo", "Kapoor (Camphor)", "Fair & Lovely 25g"). These are 
> legitimate product names. The earlier rule ("letters, numbers, spaces, hyphens only") 
> was too restrictive. Updated to allow `&` and `()` as well.

### 5.6 User Profile Rules

| Rule | Detail |
|---|---|
| Display name: optional, max 80 chars | Letters, spaces, hyphens, apostrophe |
| Shop name: optional, max 50 chars | Letters, spaces — used on every bill PDF |
| Email: read-only | Managed by Google Auth |
| If shop name blank: PDF shows "आपकी दुकान" | Default fallback |

> **Audit finding — shop name:** 5 users have email-style shop names with dots
> ("deepak.alok", "ankesh.codeinit"). These appear to be test/dev accounts where the
> email prefix was auto-filled as shop name. **Decision: leave existing data as-is.**
> Going forward, the input field will accept only letters and spaces, and the onboarding
> screen will add hint text: "अपनी दुकान का नाम लिखें (जैसे: Sharma General Store)"

---

## 6. Input Validation Rules — All Fields

To be implemented in `lib/utils/validators.dart` (Flutter) — mirrors admin's `lib/validators.ts`.

| Field | Min | Max | Allowed chars | Notes |
|---|---|---|---|---|
| Display name | 0 (optional) | 80 | Letters, spaces, hyphens, apostrophe | Strip HTML |
| Shop name | 0 (optional) | 50 | Letters, spaces | Hint: no dots, no @, no numbers |
| Customer name | 1 (required) | 60 | Letters, spaces, hyphens | No digits, no special chars |
| Phone number | 10 (if provided) | 10 | Digits only | Auto-strip `+91` prefix if present; show inline note: "सिर्फ 10 अंक लिखें, +91 नहीं" |
| Tag | 0 (optional) | 30 | Letters, spaces, hyphens | |
| Opening balance | -99,999 | 99,999 | Numbers, one decimal | Negative = customer has credit |
| Item name | 3 | 50 | Letters, numbers, spaces, hyphens, `&`, `()` | Updated from earlier draft |
| Alias (bolne ka naam) | 2 | 50 | Letters, spaces, Devanagari | |
| Selling price | 0 | 49,999 | Numbers, one decimal | No negative |
| Current stock | 0 | 1,00,000 | Whole numbers only | |
| Low stock limit | 1 | 9,99,999 | Whole numbers only | |
| Discount | 0 | < bill subtotal | Numbers, one decimal | Cannot equal subtotal |
| Payment amount | 0.01 | No hard cap | Numbers, one decimal | Overpayment allowed |

---

## 7. Reports & Stats — What Shows Where

| Screen | Source | Filter | Excludes |
|---|---|---|---|
| Dashboard — Today | `past_bills` | `created_at >= IST midnight today` | `transaction_type = 'payment'` |
| Dashboard — This Month | `past_bills` | `created_at >= IST month start` | `transaction_type = 'payment'` |
| Dashboard — Customer credit | `past_bills` by customer | outstanding < 0 | — |
| Reports — Custom Range | `past_bills` | User dates (IST, both ends inclusive) | `transaction_type = 'payment'` |
| Khata — कुल बकाया | `customers.opening_balance` + `past_bills by customer_id` | All time | Nothing — needs both types |
| Item Detail — Monthly Sales | `past_bills.bill_details` | Current month IST | `transaction_type = 'payment'` |

**Date boundary rule:** always use IST midnight as day boundary. Always `.toUtc()` before querying.

---

## 8. Sprint Plan

### Sprint 1 — Foundation (no migration risk)
1. Fix timezone: `.toUtc()` everywhere
2. Fix shopName → global state → PDF
3. Filter `transaction_type = 'payment'` from bill counts and sales totals
4. Phone number: auto-strip `+91` prefix in input field + show hint

### Sprint 2 — Schema Migration (after data audit sign-off)
1. Add `customer_id` FK, `transaction_type`, `customer_no`, `tag`, `is_active` columns
2. Add phone uniqueness constraint
3. Backfill `customer_id` links where name matches (audit-verified rows only)
4. Do NOT auto-backfill `transaction_type` — see Section 9

### Sprint 3 — Input Validation (bulk fix ~25 bugs)
1. Create `lib/utils/validators.dart`
2. Apply to all forms: customer, inventory, billing discount, payment, profile

### Sprint 4 — Customer Ledger Redesign
1. Build reusable customer combo box component
2. Replace customer field in billing settlement + customer management entry
3. Fix कुल बकाया: include `opening_balance`, use `customer_id` for queries
4. Fix outstanding display: ₹3,090 not ₹3.0K
5. Implement deactivation policy
6. Negative balance display (green "जमा" vs red "बकाया")

### Sprint 5 — Advance / Overpayment
1. Relax payment cap and opening_balance constraint
2. Update ledger formula for negative balance
3. Dashboard: show "total outstanding" and "total customer credit" separately

### Sprint 6 — Inventory Edit Redesign
1. Edit by item ID not name
2. Category/unit dropdowns in edit mode
3. Duplicate name check on save with proper error

### Sprint 7 — Navigation & UX Polish
1. Clear route stack on logout
2. "Discard changes?" dialog — global across all forms
3. Save button SafeArea fix
4. App restart → always home tab

---

## 9. Data Audit Process — Rules for All Future Backfills

Before any new constraint is applied to existing tables, run an **audit-first** pass.

**Why this matters for `transaction_type`:** the obvious backfill strategy is to look for
payment records by scanning `bill_details::text ILIKE '%भुगतान%'`. This is unreliable:
- False positives if any item name or note happens to contain that word
- False negatives if payment records used different wording or structure
- No confidence score — wrong classification looks identical to correct one

**Process:**
1. Run audit script → report violation counts and sample rows per rule → no writes
2. Manually review sample (20 rows per category)
3. Decide fix strategy per category before any migration script runs:
   - Truncate
   - Leave existing as-is, enforce on new writes only
   - Manual correction

Audit script: `supabase/data_audit.sql` (paste into Supabase SQL editor)

---

## 10. Data Audit Results — 2026-08-17

**Rows audited:** 22 users · 31 customers · 187 inventory items · 0 stock rows (RLS blocks anonymous)

| Field | Finding | Decision |
|---|---|---|
| `users.shop_name` | 5 users have email-style names with dots (e.g. "deepak.alok") | Leave as-is. Enforce letters+spaces on new writes. Add onboarding hint |
| `customers.name` | 1 customer named "450" (number as name) | Leave as-is. Test data |
| `customers.phone` | 1 garbage phone `",()())(())(***"` | Leave as-is. Test data. Enforce 10-digit on new writes |
| `customers.name` | 1 duplicate "sanky test" (2 records same user) | Leave as-is. Duplication is now intentionally allowed |
| `master_inventory.item_name` | 25 items with `&`, `()` (e.g. "Head & Shoulders") | Update validation rule to allow `&` and `()` — these are real product names |
| `master_inventory.item_name` | 1 item > 50 chars (Devanagari spam string) | Leave as-is. Enforce max 50 on new writes |
| `user_stock.*` | All clean (0 violations) — but 0 rows returned (RLS) | RLS is correctly blocking anonymous access to stock. ✅ |

**Phone summary:**
- 11 valid (10 digits) · 19 NULL · 0 with +91 prefix · 1 garbage

**Overall:** existing data is clean enough to enforce constraints on new writes immediately
without a migration pass. Only inventory item names need a rule relaxation (allow `&`, `()`).

---

## 11. What Does NOT Need Rebuilding

| Component | Status |
|---|---|
| `buildBillPdfBytes()` — PDF generation | ✅ Already unified. Just fix shopName passing |
| `bill_card.dart` — bill detail sheet + PDF trigger | ✅ Shared between past bills and ledger |
| Voice transcription + matching (Cloud Run) | ✅ Live and healthy |
| Admin force-dynamic caching | ✅ Done on all 6 pages |
| Backend HMAC auth | ✅ Secure |
| Supabase RLS (user_id filter on stock) | ✅ Correctly blocking anonymous reads |
