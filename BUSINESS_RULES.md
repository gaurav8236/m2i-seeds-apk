# SmartDukan — Business Rules, Data Schema & Architecture Plan

> This is a planning document. No code changes live here.  
> Date: 2026-08-17  
> Status: Draft — to be reviewed and agreed before implementation begins.

---

## 1. PDF Architecture — Current State vs Correct State

### What we found in the code

**Good news:** The PDF code IS already unified in one place:
```
lib/utils/bill_pdf.dart → buildBillPdfBytes()
```
Both `bill_card.dart` (past bills + customer ledger) and `voice_billing_screen.dart` (new bill) call the same function. **There is no duplicate PDF code.**

**The actual bug** is that `shopName` is never passed to `buildBillPdfBytes()` from either caller — so it always falls back to `'आपकी दुकान'`. The function signature accepts `shopName` but nobody fills it in.

### Rule going forward

> **One function. One format. Always.**  
> `buildBillPdfBytes()` is the single source of truth.  
> Any new screen that generates a PDF must call this function — never write PDF layout code inline anywhere else.  
> `shopName` must always be fetched from the user's profile and passed in.

### How shopName flows (plan)
```
App startup → fetch user profile → store in global state / provider
     ↓
Any PDF generation → read shopName from global state → pass to buildBillPdfBytes()
```
No screen should fetch shop name on its own at PDF-generation time. It should already be in memory.

---

## 2. Timezone — India (IST) Everywhere

### Rule

> **All times are IST (UTC+5:30). Always. No exceptions.**

### Current problem

`DateTime.now()` in Dart returns local device time. When sent to Supabase without `.toUtc()`, it is stored with no timezone marker — Supabase reads it as UTC and it ends up 5h 30m wrong.

### Plan

| Location | Change |
|---|---|
| All date filters in `supabase_service.dart` | `.toUtc().toIso8601String()` |
| `auth_service.dart` user creation | `.toUtc().toIso8601String()` |
| PDF date display | Use `bill.createdAt` (from DB) — parse and display in IST using `intl` package |
| Bill card date display | Same — parse DB timestamp, show in IST |
| Reports date boundary (start of day) | `DateTime(year, month, day)` is local midnight IST — add `.toUtc()` before sending to query |

### IST display helper (to be created)
```dart
// lib/utils/date_utils.dart
String fmtDateIST(DateTime utcTime) {
  final ist = utcTime.toLocal(); // device is IST → toLocal() gives IST
  return DateFormat('d MMM yyyy, h:mm a').format(ist);
}
```
Every screen uses this one function for display. Never call `.format()` on a raw DateTime directly.

---

## 3. Admin Panel — Data Refresh Strategy

### Decision

> **No realtime subscription needed.**  
> Admin is an operations tool, not a live dashboard. Reload on page visit is sufficient.

### Current state (already done)
All 6 admin data pages have `export const dynamic = 'force-dynamic'` and `export const fetchCache = 'force-no-store'`. This means every page load fetches fresh data from Supabase. ✅

### Rule going forward
> Never add `export const revalidate = N` to admin pages.  
> Never cache admin data at the component level.  
> If a user needs fresher data, they reload the page.

---

## 4. Data Schema — Current Problems & Proposed Fix

### 4.1 Current Schema (simplified)

```
customers
  id UUID PK
  user_id UUID FK → users
  name TEXT              ← identity is just a string
  phone TEXT
  opening_balance FLOAT

past_bills
  id UUID PK
  user_id UUID FK → users
  customer_name TEXT     ← ⚠️ string copy, not a FK to customers.id
  total_amount FLOAT
  discount_amount FLOAT
  is_credit BOOLEAN      ← used for both sales AND payment records
  bill_details JSONB     ← item list snapshot
  created_at TIMESTAMPTZ
```

### 4.2 Problems with current schema

| Problem | Impact |
|---|---|
| `customer_name` is a string, not a FK | Rename customer → all bill history orphaned (Bug #52) |
| No case-normalization on customer name | "Ram" and "ram" = two different customers (Bug #42) |
| No `transaction_type` field | Payments (Udhar recovery) counted same as sales (Bugs #6, #9, #15) |
| No phone uniqueness constraint | Duplicate phones for different customers (Bug #40) |
| `opening_balance` not included in कुल बकाया | Bug #48 — outstanding calculation wrong |

### 4.3 Proposed Schema Changes

```sql
-- ── CUSTOMERS ──────────────────────────────────────────────────────────────

-- Normalize name to lowercase for uniqueness (store original case, compare lowercase)
ALTER TABLE customers
  ADD COLUMN name_normalized TEXT GENERATED ALWAYS AS (lower(trim(name))) STORED;

ALTER TABLE customers
  ADD CONSTRAINT customers_name_unique_per_user UNIQUE (user_id, name_normalized);

ALTER TABLE customers
  ADD CONSTRAINT customers_phone_unique_per_user UNIQUE (user_id, phone);

ALTER TABLE customers
  ADD CONSTRAINT customers_phone_length CHECK (phone IS NULL OR length(phone) = 10);

ALTER TABLE customers
  ADD CONSTRAINT customers_opening_balance_positive CHECK (opening_balance >= 0);

-- ── PAST_BILLS ─────────────────────────────────────────────────────────────

-- Add customer_id as proper FK (allow NULL for walk-in/cash customers)
ALTER TABLE past_bills
  ADD COLUMN customer_id UUID REFERENCES customers(id) ON DELETE SET NULL;

-- Add transaction type to distinguish sales from payment receipts
ALTER TABLE past_bills
  ADD COLUMN transaction_type TEXT NOT NULL DEFAULT 'sale'
  CHECK (transaction_type IN ('sale', 'payment'));

-- Backfill: existing payment records (item_name = 'भुगतान') → mark as 'payment'
UPDATE past_bills
SET transaction_type = 'payment'
WHERE bill_details::text ILIKE '%भुगतान%';
```

### 4.4 How customer_id gets linked

When creating a bill with a customer name:
1. Look up `customers.id` by `user_id + lower(name)`
2. Write `customer_id` to `past_bills` alongside the existing `customer_name` (keep name as snapshot for display)
3. Rename/edit customer → update `customers.name` only. Bills retain `customer_id` and display via JOIN if needed.

> **Keep `customer_name` as a snapshot column** — it preserves what was on the bill at time of sale, even if customer is later renamed. `customer_id` is used for lookups and ledger aggregation.

---

## 5. Business Rules

These are the non-negotiable rules of how SmartDukan works. All validation, UI, and backend logic must enforce these.

### 5.1 Billing Rules

| Rule | Detail |
|---|---|
| Bill amount ≥ ₹0 | A bill cannot be for negative money |
| Discount ≥ ₹0 | No negative discounts. Discount is a reduction only |
| Discount < total bill amount | Discount cannot exceed or equal the bill subtotal (grand total must be > ₹0) |
| Stock deduction ≤ available stock | Cannot bill more than what's in stock |
| Bill must have at least 1 item | Empty bill cannot be created |
| Bill type is either Naqad (cash) or Udhar (credit) — not both | One bill = one payment type. If a customer pays part cash and part credit, those are two separate transactions |
| Discount resets when cart changes | Discount is tied to the full cart — if items are added/removed, discount field clears |
| Bill is immutable after creation | Past bills cannot be edited. Only new transactions can be added |

### 5.2 Customer / Khata Rules

| Rule | Detail |
|---|---|
| Customer name is unique per shopkeeper (case-insensitive) | "Ram", "ram", "RAM" → same customer |
| Phone number is exactly 10 digits, numeric only | No country code, no spaces, no alphabets |
| Phone is unique per shopkeeper | Two customers cannot share the same phone number |
| Customer name cannot be blank | Required field |
| Opening balance ≥ ₹0 | "पहले से बकाया" is the amount the customer owed before using the app — cannot be negative |
| Renaming a customer does not affect bill history | History is linked by customer_id, not name |
| Customer deletion: decide policy | Options: soft delete (mark inactive) OR block if outstanding > 0 |

### 5.3 Sales vs Customer Ledger — Two Separate Concerns

> This is the most important business rule to get right.

**Sales / Revenue** answers: *"How much did I sell today/this month?"*
- Source: `past_bills WHERE transaction_type = 'sale'`
- Includes: all sale bills (Naqad + Udhar)
- Excludes: payment receipts (`transaction_type = 'payment'`)
- Used in: Reports screen, Dashboard stats

**Customer Ledger (Khata)** answers: *"How much does this customer owe me?"*
- Formula: `opening_balance + sum(sale bills) - sum(payment receipts)`
- Source: `customers.opening_balance` + `past_bills WHERE customer_id = X`
- Split by transaction_type inside the same table
- Used in: Khata screen, Customer detail, कुल बकाया

**These two must never be mixed:**
```
Total Sales ≠ Total Outstanding
Sales includes all bills.
Outstanding = only unpaid Udhar minus payments received.
```

### 5.4 Payment / Udhar Recovery Rules

| Rule | Detail |
|---|---|
| Payment amount > ₹0 | Cannot record a payment of ₹0 or negative |
| Payment ≤ outstanding balance | Overpayment is a separate flow (advance) — not yet implemented |
| Payment is recorded as `transaction_type = 'payment'` | NOT counted in billing count or sales total |
| Payment does NOT create an item entry | No item in `bill_details` for payment records. Or use a placeholder that's clearly marked |
| Payment reduces customer outstanding | `outstanding = opening_balance + Σsales - Σpayments` |

### 5.5 Inventory Rules

| Rule | Detail |
|---|---|
| Item name is unique per shopkeeper's inventory | Case-insensitive, minimum 3 chars, maximum 50 chars |
| Selling price ≥ ₹0 and < ₹50,000 | No negative prices. No unrealistic prices |
| Stock quantity ≥ 0 and ≤ 1,00,000 | Integer only |
| Low stock limit ≥ 1 | Must set a minimum threshold |
| Aliases (bolne ka naam) are unique per item | No duplicate aliases |
| Alias count ≤ 10 per item | Max 10 voice-recognition aliases |
| Editing item name: updates existing item, does NOT create new | Edit flow must pass item ID |
| Deleting an item with past bills: retain snapshot in bill_details | Never cascade delete bill data |

### 5.6 User Profile Rules

| Rule | Detail |
|---|---|
| Display name: optional, max 80 chars, letters/spaces/hyphens only | No numbers, no special chars |
| Shop name: optional, max 50 chars, letters/spaces only | Appears on every bill PDF |
| Email: read-only, managed by Google Auth | Cannot be changed in-app |
| If shop name is blank: PDF shows "आपकी दुकान" | Default fallback only if not set |

---

## 6. Input Validation Rules (All Fields)

To be implemented in `lib/utils/validators.dart` (Flutter) — mirrors admin's `lib/validators.ts`.

| Field | Min | Max | Allowed | Not Allowed |
|---|---|---|---|---|
| Display name | 0 (optional) | 80 | Letters, spaces, hyphens, apostrophe | Numbers, special chars, HTML |
| Shop name | 0 (optional) | 50 | Letters, spaces | Numbers, special chars |
| Customer name | 1 (required) | 60 | Letters, spaces, hyphens | Numbers, special chars, only-spaces |
| Phone number | 10 (required if entered) | 10 | Digits only | Alphabets, +, spaces, special chars |
| Opening balance | 0 | 99,999 | Numbers, one decimal | Negative, alphabets |
| Item name | 3 | 50 | Letters, numbers, spaces, hyphens | Special chars |
| Alias (bolne ka naam) | 2 | 50 | Letters, spaces | Special chars |
| Selling price | 0 | 49,999 | Numbers, one decimal | Negative |
| Current stock | 0 | 1,00,000 | Whole numbers only | Decimals, negative |
| Low stock limit | 1 | 9,99,999 | Whole numbers only | Decimals, negative, 0 |
| Discount | 0 | < bill total | Numbers, one decimal | Negative, > bill total |
| Payment amount | 1 | ≤ outstanding | Numbers, one decimal | Negative, 0, > outstanding |

---

## 7. Reports & Stats — What Shows Where

| Screen | Data Source | Filter | Excludes |
|---|---|---|---|
| Dashboard — Today's Sales | `past_bills` | `created_at >= today_IST_midnight` | `transaction_type = 'payment'` |
| Dashboard — This Month | `past_bills` | `created_at >= month_start_IST` | `transaction_type = 'payment'` |
| Reports — Custom Range | `past_bills` | User-selected dates (IST, inclusive both ends) | `transaction_type = 'payment'` |
| Khata — कुल बकाया | `customers.opening_balance` + `past_bills by customer_id` | All time | Nothing — needs both sales AND payments |
| Khata — Date-filtered view | `past_bills by customer_id` | Date range | Nothing — shows full ledger history |
| Item Detail — Monthly Sales | `past_bills.bill_details` | Current month IST | `transaction_type = 'payment'` |

### Rule
> `transaction_type = 'payment'` rows are **never included in sales figures**.  
> They are **only used in the customer ledger calculation**.  
> The date range filter for reports uses **IST midnight as day boundary** — always `.toUtc()` before querying.

---

## 8. Feature Work Order (Proposed Sprints)

Based on business impact and dependency order:

### Sprint 1 — Foundation (schema + timezone + PDF shop name)
1. Run schema migrations (customer_id FK, transaction_type, constraints)
2. Fix timezone: `.toUtc()` everywhere in supabase_service + auth_service
3. Fix shopName passing to `buildBillPdfBytes()` — pull from global user state
4. Fix billing count: filter `transaction_type = 'payment'` out of bill counts
5. Fix sales total: same filter

### Sprint 2 — Input Validation (bulk fix ~25 bugs)
1. Create `lib/utils/validators.dart` in Flutter
2. Apply to: customer form, inventory form, billing discount field, payment amount field, profile form

### Sprint 3 — Customer Ledger Redesign
1. Link `past_bills.customer_id` on checkout
2. Fix कुल बकाया calculation to include `opening_balance`
3. Fix outstanding display: don't abbreviate (₹3,090 not ₹3.0K)
4. Fix customer rename: update `customers.name` only, history stays via `customer_id`
5. Case-insensitive duplicate check on customer create/edit

### Sprint 4 — Inventory Edit Redesign
1. Edit flow uses item ID not name
2. Category/Unit dropdowns in edit mode
3. Duplicate name check on save (with proper error)

### Sprint 5 — Navigation & UX
1. Clear route stack on logout
2. "Discard changes?" dialog pattern — global across all forms
3. Save button layout (SafeArea fix)
4. App restart → always home tab

---

## 9. What Does NOT Need Rebuilding

| Thing | Status |
|---|---|
| PDF generation code | ✅ Already unified in `buildBillPdfBytes()` — just fix shopName |
| Bill card / detail sheet | ✅ Works, shared between past bills and ledger |
| Voice transcription flow | ✅ Cloud Run backend working |
| Admin force-dynamic caching | ✅ Already done on all 6 pages |
| Backend auth (HMAC) | ✅ Already secure |
| Supabase RLS (user_id filter) | ✅ Already applied |
