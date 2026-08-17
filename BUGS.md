# SmartDukan — Bug Tracker & Feature Plan

> Statuses: 🔴 Open · 🟡 In Progress · ✅ Fixed · 🏗️ Needs Redesign · 📐 Schema Change Required

---

## QA Session — 2026-08-17

**Total bugs reported:** 56 (55 Bugs + 1 Improvement)  
**Reporters:** Mayank (#1), Ankesh (#2–56)  
**Source:** QA Issues PDF — Smart Dukan QA Round 1

---

## Platform Feature Map

Below are all major features of SmartDukan and how they interconnect across the Flutter app, Admin panel, and Backend.

```
┌─────────────────────────────────────────────────────────────────┐
│                        FLUTTER APP                              │
│                                                                 │
│  F1: Auth/Profile ──────────────────────────────────────────   │
│       └── Google Login → users table → shop_name / display_name│
│                                                                 │
│  F2: Inventory Management ──────────────────────────────────── │
│       └── master_inventory + user_stock tables                  │
│       └── upsert_inventory_item (Supabase RPC)                  │
│       └── stock_history (restock log)                           │
│                                                                 │
│  F3: Voice Billing ──────────────────────────────────────────  │
│       └── /voice-search/ (Cloud Run) → transcribe → match stock │
│       └── /voice-checkout/ (Cloud Run) → save bill + stock      │
│       └── past_bills table                                      │
│       └── bill_pdf.dart → PDF generation                        │
│                                                                 │
│  F4: Customer / Khata (Udhar) ──────────────────────────────── │
│       └── customers table (name, phone, opening_balance)        │
│       └── past_bills.customer_name (STRING FK ← root cause)     │
│       └── Payment via /voice-checkout/ (is_credit: false)       │
│                                                                 │
│  F5: Reports & Stats ───────────────────────────────────────── │
│       └── fetchFilteredStats() — date range queries on past_bills│
│       └── Khata report — aggregates from past_bills             │
│       └── Custom date picker                                    │
│                                                                 │
│  F6: App Navigation / State ───────────────────────────────────│
│       └── TabBar (Home/Stock/Khata/Reports/Profile)             │
│       └── draft_service.dart (unsaved state)                    │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                       ADMIN PANEL (Web)                         │
│                                                                 │
│  A1: Dashboard — today's stats, user count, recent bills        │
│  A2: Users — list of all registered shopkeepers                 │
│  A3: Inventory — master_inventory CRUD (item_name, category etc)│
│  A4: Logs — stock_history + activity logs                       │
│  A5: Admins — manage admin users                                │
│  A6: Profile — admin profile settings                           │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                       BACKEND (Cloud Run)                       │
│                                                                 │
│  /voice-search/   → Groq Whisper → LLM → inventory match       │
│  /voice-checkout/ → update user_stock + insert past_bills       │
│  /health          → env var check                               │
└─────────────────────────────────────────────────────────────────┘
```

---

## Feature → Bug Correlation

### F1 · Auth / User Profile
**Bugs:** #2, #8, #10, #11, #12, #13, #14, #56

| # | Bug | Type | Fix Level |
|---|---|---|---|
| 2 | New user from app not shown in admin dashboard | Bug | Admin cache/realtime |
| 8 | Bill PDF shows "Apki Dukan" instead of shop name | Bug | Pull `shop_name` from user profile in bill_pdf.dart |
| 10 | Shop name + customer name allow blank/empty on save | Bug | Validation |
| 11 | Name accepts only spaces or special characters | Bug | Validation |
| 12 | Dashboard layout breaks on long name/shop name | Bug | UI — text overflow handling |
| 13 | Back navigation after logout redirects to logout screen | Bug | Auth state / route stack reset |
| 14 | Shop name allows long text and special characters | Bug | Validation |
| 56 | App retains previous screen after restart | Bug | App startup route logic |

**Root cause cluster:** No validation on profile inputs + auth route stack not cleared on logout.

---

### F2 · Inventory Management (Flutter App)
**Bugs:** #4, #5, #17, #19, #20, #21, #22, #23, #24, #25, #26, #27, #28, #29, #30, #32

| # | Bug | Type | Fix Level |
|---|---|---|---|
| 4 | Numeric values accepted in Unit field (admin) | Bug | Validation — admin side |
| 5 | Unit value not updated in existing inventory item | Bug | Edit flow / upsert logic |
| 17 | Category/Unit auto-populate wrong when item selected | Bug | Dropdown state management |
| 19 | Incorrect monthly purchase count on item detail | Bug | Query / timezone bug |
| 20 | Error when updating current stock on item detail | Bug | API / RPC error |
| 21 | Special characters allowed in item name | Bug | Validation |
| 22 | Editing item name creates a NEW item instead of updating | 🏗️ Redesign | Edit vs create logic broken — `upsert_inventory_item` creates on name change |
| 23 | Category/Unit dropdowns missing in edit mode | Bug | UI — edit form state |
| 24 | No max char limit on item name / bolne ka naam | Bug | Validation |
| 25 | No error when adding item with existing name (only qty updated silently) | Bug | UX — silent upsert needs user feedback |
| 26 | Negative price allowed | Bug | Validation |
| 27 | Decimal price shown in list but not on detail/edit | Bug | UI — number formatting |
| 28 | Negative unit value allowed | Bug | Validation |
| 29 | Decimal unit shown in list but not on detail/edit | Bug | UI — number formatting |
| 30 | No error when duplicate "bolne ka naam" alias added | Bug | Validation / duplicate check |
| 32 | No error when renaming item to existing name | Bug | Duplicate check on update |

**Root cause cluster:** The inventory edit flow conflates create and edit. `upsert_inventory_item` RPC uses item name as the key — if name changes, it creates a new item. **#22 requires redesign of the edit flow to use item ID instead of name as the upsert key.**

---

### F3 · Voice Billing / Bill Generation
**Bugs:** #1, #6, #15, #33, #34, #35, #46, #53, #54

| # | Bug | Type | Fix Level |
|---|---|---|---|
| 1 | Bill PDF: "dinak" and "grahak" labels wrong | Improvement | bill_pdf.dart — label strings |
| 6 | Billing count increases on each partial Udhar payment | 🏗️ Redesign | Payment via /voice-checkout/ creates new bill entry — counts as bill |
| 15 | Different bills for same invoice with Udhar + Nagad | 🏗️ Redesign | Split billing logic — each payment type creates separate bill record |
| 33 | Can bill quantity greater than available stock | Bug | Backend validation in /voice-checkout/ — check stock before deducting |
| 34 | Discount not reset when item deleted/added during billing | Bug | Billing screen state — discount tied to cart, not items |
| 35 | No error for invalid discount field input | Bug | Validation |
| 46 | Customers not shown in dropdown during bill creation | Bug | fetchCustomerNames() / timing issue |
| 53 | Negative discount allowed — increases total bill | Bug | Validation |
| 54 | No error when discount > total bill amount | Bug | Validation |

**Root cause cluster:** Bills and payments both write to `past_bills` with no distinction between "sale" and "payment received" at count level. #6 and #15 are the same root cause — **schema needs a `transaction_type` field or separate `payments` table**. Also no server-side validation on discount or stock quantity.

---

### F4 · Customer / Khata (Udhar) Management
**Bugs:** #36, #37, #38, #39, #40, #41, #42, #43, #44, #45, #46, #47, #48, #49, #50, #51, #52, #55

| # | Bug | Type | Fix Level |
|---|---|---|---|
| 36 | Customer added on app not updated in admin dashboard | Bug | Realtime/sync issue |
| 37 | Special characters allowed in customer name | Bug | Validation |
| 38 | Phone number > 10 digits allowed | Bug | Validation |
| 39 | Alphabets allowed in phone number field | Bug | Validation — input type |
| 40 | Duplicate phone number allowed for different customers | Bug | DB unique constraint missing |
| 41 | Wrong error message when renaming to existing customer name | Bug | Error message copy |
| 42 | Same name with different casing treated as different customer | 📐 Schema | Normalize to lowercase before save + unique constraint |
| 43 | No error for negative "पहले से बकाया" value | Bug | Validation |
| 44 | No error for invalid "पहले से बकाया" value | Bug | Validation |
| 45 | Extremely long customer name allowed | Bug | Validation — max char limit |
| 47 | "कुल बकाया" wrong when no entries for today filter | Bug | Timezone bug — date boundary filter |
| 48 | "कुल बकाया" not shown for customer with existing balance | Bug | opening_balance not included in calculation |
| 49 | 404 error on payment button | Bug | Backend URL was Railway (now fixed with Cloud Run) |
| 50 | No error for negative/invalid payment amount | Bug | Validation |
| 51 | Can clear name + phone and save customer | Bug | Required field validation on save |
| 52 | History disappears when customer name is changed | 📐 Schema | **Critical** — `past_bills.customer_name` is a string FK, not an ID. Name change breaks all bill history |
| 55 | ₹3,090 displayed as ₹3.0K instead of full amount | Bug | `fmtCurrency()` — threshold too low, needs config |

**Root cause cluster:** The biggest structural issue is #52 — **customer identity is stored as a name string in `past_bills` table, not as a `customer_id` foreign key**. This is a schema-level redesign. When name changes, all history is orphaned. Bugs #41 and #42 (casing) are part of the same root cause.

---

### F5 · Reports & Stats
**Bugs:** #7, #9, #16, #47

| # | Bug | Type | Fix Level |
|---|---|---|---|
| 7 | Incorrect time shown on bill PDF + app dashboard (IST vs UTC) | 📐 Schema | `DateTime.now().toIso8601String()` — must use `.toUtc()` everywhere |
| 9 | Total sales wrong after partial Udhar repayment | 🏗️ Redesign | Payments counted in sales total — needs `transaction_type` filter |
| 16 | Current date not shown in custom date range (yesterday to today) | Bug | Date range query — boundary is exclusive, should be inclusive |
| 47 | "कुल बकाया" wrong on today filter | Bug | Timezone bug — same root as #7 |

**Root cause cluster:** #7 and #47 are both the timezone bug (already identified — `DateTime.now()` without `.toUtc()`). #9 is the same root cause as #6 — payments and sales mixed in `past_bills`.

---

### F6 · App Navigation / UX
**Bugs:** #13, #18, #31, #56

| # | Bug | Type | Fix Level |
|---|---|---|---|
| 13 | Back after logout goes to logout screen | Bug | Clear navigation stack on signOut |
| 18 | Save button truncated at bottom across app | Bug | UI layout — SafeArea/padding issue |
| 31 | Unsaved entries not discarded on back navigation (**all screens**) | 🏗️ Redesign | Global — needs "discard changes?" confirmation dialog pattern across app |
| 56 | App shows previous screen after restart | Bug | Startup route checks auth state but doesn't reset to home tab |

---

## Cross-Feature Root Causes (High Priority)

These are not isolated bugs — they are **systemic issues** affecting multiple features:

### 1. 🔴 No centralized input validation (affects ~25 bugs)
**Bugs:** #3, #4, #10, #11, #14, #21, #24, #26, #28, #30, #37, #38, #39, #43, #44, #45, #50, #51, #53, #54  
**Plan:** Create a shared `lib/utils/validators.dart` in Flutter (mirrors what admin panel already has in `lib/validators.ts`). Apply to all form fields across all screens.

### 2. 🔴 Timezone bug — `DateTime.now()` without `.toUtc()` (affects #7, #16, #47)
**Bugs:** #7, #47 (display), #16 (filter), + every date-range query in reports  
**Plan:** Replace all `DateTime.now().toIso8601String()` with `DateTime.now().toUtc().toIso8601String()`. Affects `supabase_service.dart` lines 116, 134–135, 347–354 and `auth_service.dart` line 44.

### 3. 📐 Customer linked by name string, not ID (affects #41, #42, #52)
**Bugs:** #52 (critical — history lost), #41, #42 (casing), #36  
**Plan:** Add `customer_id UUID FK` column to `past_bills`. Migrate existing records. All queries join on ID not name. **Schema migration required.**

### 4. 📐 No distinction between bills and payments in `past_bills` (affects #6, #9, #15)
**Bugs:** #6 (billing count), #9 (sales total), #15 (split bills)  
**Plan:** Add `transaction_type ENUM('sale', 'payment')` column to `past_bills`. Filter stats queries by type. Payment entries excluded from billing count and sales total.

### 5. 🏗️ Inventory edit uses name as upsert key, not ID (affects #22, #25, #32)
**Bugs:** #22 (new item on rename), #25 (silent qty update), #32 (no error on duplicate name)  
**Plan:** Edit flow must pass `item_id` to backend. `upsert_inventory_item` RPC needs to accept ID for updates vs null for inserts. Separate edit and create paths explicitly.

### 6. 🏗️ Unsaved state not managed globally (affects #31 — all screens)
**Bug:** #31  
**Plan:** Implement a global `FormDirtyState` provider. On back navigation, if dirty → show "Discard changes?" dialog. Apply to: inventory add/edit, customer add/edit, billing screen, profile screen.

---

## Fix Priority Plan

### 🔥 P0 — Critical (data integrity / app crash)
| Bug | Feature | Why Critical |
|---|---|---|
| #52 | Customer/Khata | History lost permanently on name change — data loss |
| #49 | Customer/Khata | 404 on payment — core feature broken (now fixed with Cloud Run URL) |
| #6 | Billing | Billing count inflated — wrong business metrics |
| #9 | Reports | Sales total wrong — business decision making affected |
| #33 | Billing | Can oversell stock — inventory goes negative |

### ⚠️ P1 — High (wrong data shown to user)
| Bug | Feature |
|---|---|
| #7, #47 | Timezone — wrong time on bills + reports |
| #15 | Split bills for same invoice |
| #22 | Item rename creates new item |
| #48 | Opening balance not in कुल बकाया |
| #8 | Wrong shop name on PDF |

### 🟡 P2 — Medium (validation missing)
Bugs: #3, #10, #11, #14, #21, #24, #26, #28, #30, #32, #34, #35, #37, #38, #39, #40, #42, #43, #44, #45, #50, #51, #53, #54  
All addressable with a shared validator utility.

### 🟢 P3 — Low (UX polish)
Bugs: #1, #12, #13, #16, #18, #23, #25, #27, #29, #31, #41, #55, #56

---

## Schema Changes Required

```sql
-- 1. Add customer_id to past_bills (links bill to customer by ID not name)
ALTER TABLE past_bills
  ADD COLUMN customer_id UUID REFERENCES customers(id) ON DELETE SET NULL;

-- 2. Add transaction_type to past_bills (separates sales from payments)
ALTER TABLE past_bills
  ADD COLUMN transaction_type TEXT NOT NULL DEFAULT 'sale'
  CHECK (transaction_type IN ('sale', 'payment'));

-- 3. Normalize customer name (case-insensitive unique)
ALTER TABLE customers
  ADD CONSTRAINT customers_user_name_unique UNIQUE (user_id, lower(name));

-- 4. Phone number unique per user
ALTER TABLE customers
  ADD CONSTRAINT customers_phone_unique UNIQUE (user_id, phone);

-- 5. Phone number max 10 digits
ALTER TABLE customers
  ADD CONSTRAINT customers_phone_length CHECK (length(phone) <= 10);
```

---

## API & Data Flow Documentation

### Voice Billing Flow (end to end)
```
User speaks → Flutter records audio (m4a)
  ↓
POST /voice-search/ (Cloud Run)
  → Groq Whisper transcribes audio
  → Groq LLM extracts items + quantities
  → Supabase: fetch user_stock JOIN master_inventory
  → Fuzzy match spoken items to inventory
  → (if not preview) UPDATE user_stock.current_stock
  ↓
Flutter shows billed items → user confirms
  ↓
POST /voice-checkout/ (Cloud Run)
  → UPDATE user_stock (final stock values)
  → INSERT past_bills (bill record with bill_details JSON)
  ↓
Flutter generates PDF (bill_pdf.dart)
  → Reads from local state (not DB re-fetch)
```

### Customer Payment Flow
```
User taps "Record Payment" → enters amount
  ↓
POST /voice-checkout/ (Cloud Run)
  → items: [{item_name: "भुगतान", is_credit: false}]
  → INSERT past_bills (transaction_type should = 'payment')
  ↓
Khata screen re-fetches past_bills
  → Aggregates credit - paid = outstanding
  ← BUG: payment bill counted in billing count (#6)
  ← BUG: payment deducted from sales total (#9)
```

### Admin ↔ App Sync
```
Flutter App writes → Supabase DB directly (via supabase-flutter client)
Admin Panel reads  → Supabase DB directly (via @supabase/supabase-js server client)

Sync mechanism: NONE currently — Admin uses force-dynamic but no realtime subscription
← BUG #2: New users not visible until admin page reload
← BUG #36: Customer changes not reflected in admin
```

---

## Open Bugs (Logged 2026-08-17)

| # | Bug | Feature | Priority | Status | Schema? |
|---|---|---|---|---|---|
| 1 | Bill PDF: "dinak"/"grahak" label wrong | F3 Billing | P3 | 🔴 Open | No |
| 2 | New user from app not in admin dashboard | F1 Profile / Admin | P1 | 🔴 Open | No |
| 3 | Special chars + alphabets in phone field | F4 Customer | P2 | 🔴 Open | No |
| 4 | Numeric in Unit field (admin) | F2 Inventory | P2 | 🔴 Open | No |
| 5 | Unit value not updated on existing item | F2 Inventory | P2 | 🔴 Open | No |
| 6 | Billing count inflates on Udhar payment | F3 Billing | P0 | 🔴 Open | Yes |
| 7 | Wrong time on bill PDF + dashboard (IST bug) | F5 Reports | P1 | 🔴 Open | No |
| 8 | PDF shows "Apki Dukan" not shop name | F3 Billing | P1 | 🔴 Open | No |
| 9 | Sales total wrong after Udhar repayment | F5 Reports | P0 | 🔴 Open | Yes |
| 10 | Blank values saved in shop/customer name | F1 Profile | P2 | 🔴 Open | No |
| 11 | Name accepts only spaces / special chars | F1 Profile | P2 | 🔴 Open | No |
| 12 | Dashboard breaks on long name | F1 Profile | P3 | 🔴 Open | No |
| 13 | Back after logout → logout screen | F6 Navigation | P3 | 🔴 Open | No |
| 14 | Shop name allows long text + special chars | F1 Profile | P2 | 🔴 Open | No |
| 15 | Udhar + Nagad in same invoice = 2 bills | F3 Billing | P1 | 🔴 Open | Yes |
| 16 | Current date missing in custom date range | F5 Reports | P3 | 🔴 Open | No |
| 17 | Category/Unit wrong on item select from dropdown | F2 Inventory | P2 | 🔴 Open | No |
| 18 | Save button truncated across app | F6 UX | P3 | 🔴 Open | No |
| 19 | Wrong monthly purchase count on item detail | F2 Inventory | P2 | 🔴 Open | No |
| 20 | Error when updating current stock on item detail | F2 Inventory | P1 | 🔴 Open | No |
| 21 | Special chars in item name allowed | F2 Inventory | P2 | 🔴 Open | No |
| 22 | Renaming item creates new item | F2 Inventory | P1 | 🏗️ Redesign | No |
| 23 | Category/Unit dropdowns missing in edit | F2 Inventory | P2 | 🔴 Open | No |
| 24 | No max char on item name / bolne ka naam | F2 Inventory | P2 | 🔴 Open | No |
| 25 | No feedback when item exists (silent qty update) | F2 Inventory | P3 | 🔴 Open | No |
| 26 | Negative price allowed | F2 Inventory | P2 | 🔴 Open | No |
| 27 | Decimal price inconsistent list vs detail | F2 Inventory | P3 | 🔴 Open | No |
| 28 | Negative unit value allowed | F2 Inventory | P2 | 🔴 Open | No |
| 29 | Decimal unit inconsistent list vs detail | F2 Inventory | P3 | 🔴 Open | No |
| 30 | No error on duplicate alias (bolne ka naam) | F2 Inventory | P2 | 🔴 Open | No |
| 31 | Unsaved entries not discarded on back (all screens) | F6 UX | P2 | 🏗️ Redesign | No |
| 32 | No error when renaming item to existing name | F2 Inventory | P2 | 🔴 Open | No |
| 33 | Can bill qty > available stock | F3 Billing | P0 | 🔴 Open | No |
| 34 | Discount not reset when item deleted/added | F3 Billing | P2 | 🔴 Open | No |
| 35 | No error for invalid discount input | F3 Billing | P2 | 🔴 Open | No |
| 36 | Customer from app not updated in admin | F4 Customer / Admin | P1 | 🔴 Open | No |
| 37 | Special chars in customer name | F4 Customer | P2 | 🔴 Open | No |
| 38 | Phone > 10 digits allowed | F4 Customer | P2 | 🔴 Open | No |
| 39 | Alphabets in phone number | F4 Customer | P2 | 🔴 Open | No |
| 40 | Duplicate phone number for different customers | F4 Customer | P2 | 🔴 Open | Yes |
| 41 | Wrong error on duplicate customer name update | F4 Customer | P3 | 🔴 Open | No |
| 42 | Same name different casing = different customer | F4 Customer | P1 | 🔴 Open | Yes |
| 43 | Negative value in पहले से बकाया | F4 Customer | P2 | 🔴 Open | No |
| 44 | Invalid value in पहले से बकाया | F4 Customer | P2 | 🔴 Open | No |
| 45 | Extremely long customer name allowed | F4 Customer | P2 | 🔴 Open | No |
| 46 | Customers not in dropdown during billing | F3 Billing | P1 | 🔴 Open | No |
| 47 | कुल बकाया wrong with today filter | F4 Customer / F5 | P1 | 🔴 Open | No |
| 48 | Opening balance not in कुल बकाया | F4 Customer | P1 | 🔴 Open | No |
| 49 | 404 on payment button | F4 Customer | P0 | ✅ Fixed | No |
| 50 | Negative/invalid payment amount allowed | F4 Customer | P2 | 🔴 Open | No |
| 51 | Can clear name + phone and save | F4 Customer | P2 | 🔴 Open | No |
| 52 | History disappears on customer name change | F4 Customer | P0 | 🔴 Open | Yes |
| 53 | Negative discount increases bill total | F3 Billing | P2 | 🔴 Open | No |
| 54 | Discount > total bill — no error | F3 Billing | P2 | 🔴 Open | No |
| 55 | ₹3,090 shown as ₹3.0K (formatting) | F4 Customer | P3 | 🔴 Open | No |
| 56 | Previous screen shown after app restart | F6 Navigation | P3 | 🔴 Open | No |

---

## Fixed Bugs

| # | Bug | Fixed On | How |
|---|---|---|---|
| 49 | 404 on payment — backend dead | 2026-08-17 | Migrated backend from Railway to Cloud Run |
