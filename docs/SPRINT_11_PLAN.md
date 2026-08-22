# SmartDukan — Product & Engineering Plan
**Branch:** `feature/redesign-v2`  
**Date:** 2026-08-20  
**Status:** 🔴 PENDING USER APPROVAL — no code changed  
**Version:** 2.0 (expanded with Customer CRM + Validation features)

---

## Part A — Carry-Over Bug Fixes (Sprint 11 Phase 1)

These were designed in v1.0 of this doc. Unchanged, still P1.

| ID | Feature | Priority | Effort |
|----|---------|----------|--------|
| F-01 | PDF Devanagari rendering broken | P1 Bug | Medium |
| F-02 | Payment/deposit records inflate sales stats | P1 Bug | Tiny |
| F-03 | WhatsApp / Share PDF missing | P2 Feature | Small |

> Full RCA, files, and acceptance criteria for F-01–F-03 are documented in the artifact (v1.0). They remain unchanged.

---

## Part B — Customer CRM + Ledger (New Features)

---

### C-01 · Customer Creation — Opening Balance Clarity + Real-Time Validation

**Priority:** P2  
**Status:** 🟡 Partial — form exists, but has UX gaps

#### What Exists
`add_customer_screen.dart` has: name, phone, `opening_balance` (a single number field labelled "पहले से बकाया").

#### Gaps Identified

**Gap 1 — Opening balance is ambiguous**  
A positive `opening_balance` means "they owe us". But there's no way to record "they have already paid us an advance" (which would be a negative opening balance / credit). The current hint text "यदि ग्राहक पर पहले से कुछ बकाया है" only covers the debt direction.

**Gap 2 — Name field accepts numbers/decimals**  
No input filter on the name field — a user can type "Ramesh 123" or "₹500". Customer names should be letters (Hindi or Latin), spaces, dots, and hyphens only.

**Gap 3 — Validation only fires on submit**  
`_formKey.currentState!.validate()` runs only when "ग्राहक जोड़ें" is tapped. Errors only appear after the button tap, not while typing. This is poor UX — the user has already moved on.

#### RCA
The form was built quickly as a functional baseline. Input filtering and real-time validation were not prioritized in the original sprint.

#### Implementation Strategy

**Opening balance UX:**  
Replace the single `TextFormField` for opening balance with a two-step question:

```
"क्या इस ग्राहक का आपसे कोई लेनदेन पहले से है?"
  [उधार बाकी है (They owe you)] ← default
  [अग्रिम दिया है (They paid in advance)]
  
  ₹ [amount field]
```

- "उधार बाकी" → `opening_balance = +amount`
- "अग्रिम" → `opening_balance = -amount` (stored as negative; ledger interprets as credit balance)

**Name validation (real-time):**
```dart
// InputFormatters to block on the TextField itself
inputFormatters: [
  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Zऀ-ॿ\s\.\-]')),
],
// validator shown below field as user types via onChanged:
onChanged: (v) {
  setState(() {
    _nameError = v.trim().isEmpty ? 'नाम ज़रूरी है'
        : v.trim().length < 2 ? 'कम से कम 2 अक्षर चाहिए'
        : null;
    _isDirty = true;
  });
},
```

**Real-time inline errors:**  
Replace `validator:` pattern with `onChanged:` updating local error strings, shown with a `Text` widget styled in red below each field. Error disappears as soon as it's fixed — do not wait for submit.

#### Files Affected
| File | Change |
|------|--------|
| `lib/screens/add_customer_screen.dart` | Replace balance field with 2-option radio + amount; add name `inputFormatters`; real-time error strings |

#### Acceptance Criteria
- [ ] Typing digits/special chars in name field: blocked in real-time (they simply don't appear)
- [ ] Name error appears below field after 1 second of idle typing if invalid
- [ ] Opening balance UI clearly shows "owe us" vs "advance" choice
- [ ] Choosing "advance" stores negative opening_balance; ledger shows it as credit

---

### C-02 · Cash Loan / Non-Billing Credit Transaction

**Priority:** P2  
**Status:** 🔴 Missing entirely

#### Business Context
Apart from selling goods on credit (billing), a shopkeeper may give a customer actual cash (informal loan). This is common in kirana relationships. This cash advance is tracked separately from goods credit — it's pure money out.

Example:
- Customer buys ₹200 of atta on udhar → **billing credit** → `transaction_type='credit'`
- Customer borrows ₹500 cash from shop → **cash loan** → *(currently no way to record this)*
- Customer pays back ₹300 → **payment** → `transaction_type='payment'`

#### RCA
The `VALID_TX_TYPES` in the backend started with `sale | credit | split | payment`. Sprint 10 added `deposit`. No one designed the "cash loan" scenario.

#### Ledger Impact
The customer ledger must show all three categories clearly:
1. **उधार (Credit from bills)** — goods taken on credit
2. **नकद उधार (Cash loan)** — cash given to customer outside billing
3. **भुगतान (Payments received)** — customer paid back anything

Running balance = `opening_balance + credit_bills + cash_loans - payments_received - advance_deposits`

#### Implementation Strategy

**Backend change (whisper-api/main.py):**
```python
VALID_TX_TYPES = {"sale", "credit", "payment", "split", "deposit", "cash_loan"}
```

**New Flutter method in `supabase_service.dart`:**
```dart
static Future<void> recordCashLoan({
  required String customerName,
  required double amount,
}) async {
  // POST to /voice-checkout/ with is_credit=true, transaction_type='cash_loan'
  // items: [{ item_name: 'नकद उधार (Cash Loan)', quantity: 1, price: amount }]
}
```

**Customer ledger fetch (`fetchCustomerLedger`):**  
Map `transaction_type='cash_loan'` to `type='cash_loan'` in the returned list.

**Running balance computation in `_CustomerDetailScreen`:**
```dart
case 'cash_loan':
  balance += amt;  // increases what customer owes
  break;
```

**UI — Add Entry dialog in customer detail:**  
Add a third option alongside "भुगतान मिला" and "अग्रिम जमा":
```
[🟠 नकद उधार]  — दुकान से नकद दिया
[🟢 भुगतान मिला] — बकाया चुकाया
[🟣 अग्रिम जमा] — पहले से पैसा दिया
```

#### Files Affected
| File | Change |
|------|--------|
| `whisper-api/main.py` | Add `'cash_loan'` to `VALID_TX_TYPES` |
| `lib/services/supabase_service.dart` | Add `recordCashLoan()` method |
| `lib/screens/reports_screen.dart` | `_CustomerDetailState._computeRunningBalances()` — handle `cash_loan`; add 3rd option in `_showAddEntryDialog()` |
| `lib/screens/reports_screen.dart` | `_ledgerRow()` — new row style for `cash_loan` type |

#### Acceptance Criteria
- [ ] "नकद उधार" option appears in the Add Entry dialog on customer detail
- [ ] Recording ₹500 cash loan increases the customer's outstanding balance by ₹500
- [ ] Ledger row for cash_loan shows distinct icon (e.g., arrow up, orange)
- [ ] Running balance after cash_loan correctly increases
- [ ] Backend accepts `cash_loan` transaction_type without error

---

### C-03 · Unified Customer Ledger (Bills + Transactions)

**Priority:** P2  
**Status:** 🟡 Partial — ledger exists but bills are missing

#### What Exists
`_CustomerDetailScreen` shows a running ledger of transactions from `fetchCustomerLedger()`, which queries `past_bills` with `is_credit` + `transaction_type` filters. Payment, deposit, credit, and split entries appear.

#### Gap
**Past bills (cash sales) do NOT appear in the ledger.** If a customer bought ₹200 of goods for cash, that transaction is invisible in the ledger view. Only credit/udhar transactions show up. This breaks the cohesive view the user wants.

Also: the ledger shows transactions from `past_bills` but through the lens of "was it credit?". A complete customer history means: every time this customer interacted with the shop — cash purchase, credit purchase, payment, loan — all in one scrollable timeline.

#### RCA
`fetchCustomerLedger()` was built specifically to track the running udhar balance. Cash (`is_credit=false`, `transaction_type='sale'`) entries were intentionally excluded since they don't affect the balance. But the user experience needs the full history visible.

#### Implementation Strategy

**Two-section ledger approach:**

```
Customer Detail Screen
├── SUMMARY HEADER (outstanding, total credit given, total received)  ← exists
├── LEDGER SECTION (सभी लेनदेन)
│   ├── [Cash sale entries from past_bills — labeled "नकद खरीद"]
│   ├── [Credit sale entries — labeled "उधार बिल"]
│   ├── [Cash loan entries — labeled "नकद उधार"]
│   ├── [Payment received — labeled "भुगतान मिला"]
│   └── [Advance deposit — labeled "अग्रिम जमा"]
│   All sorted newest-first. Each row shows: date, type badge, amount, running balance.
```

**Backend fetch change:** `fetchCustomerLedger()` should no longer filter by `is_credit`. Return ALL `past_bills` rows for this customer, sorted by `created_at`. Let the UI classify and style each.

```dart
// supabase_service.dart — fetchCustomerLedger()
// Remove: any is_credit filter
// Add: return all rows, let the type mapping handle display
```

Running balance computation: cash sales do NOT affect outstanding, so their balance column repeats the previous balance (no change in what they owe).

**Ledger row types and visual treatment:**

| transaction_type | is_credit | Display label | Icon | Color | Balance effect |
|-----------------|-----------|---------------|------|-------|----------------|
| sale | false | नकद खरीद | 🛒 | grey | none |
| credit | true | उधार बिल | 🔴 | red | +amount |
| split | true | आंशिक उधार | 🟠 | orange | +(amount-nagad) |
| cash_loan | true | नकद उधार | 💸 | orange | +amount |
| payment | false | भुगतान मिला | 🟢 | green | -amount |
| deposit | false | अग्रिम जमा | 🟣 | purple | -amount |

#### Files Affected
| File | Change |
|------|--------|
| `lib/services/supabase_service.dart` | `fetchCustomerLedger()` — remove is_credit filter; return all rows |
| `lib/screens/reports_screen.dart` | `_computeRunningBalances()` — cash/sale rows don't change balance; `_ledgerRow()` — new display labels and icons per type |

#### Acceptance Criteria
- [ ] Customer ledger shows ALL transactions (cash + credit + payments) in one list
- [ ] Cash sale rows are visible with "नकद खरीद" label, grey styling, no balance change
- [ ] Credit/split rows show running balance increasing
- [ ] Payment rows show running balance decreasing
- [ ] Newest entries shown first (existing behaviour preserved)
- [ ] Running balance is correct even with cash sale rows interspersed

---

### C-04 · Customer Profile — Aggregated View

**Priority:** P2  
**Status:** 🟡 Header exists; needs enhancement

#### What Exists
`_CustomerDetailScreen` header shows 3 tiles: "उधार दिया", "नकद मिला", balance.

#### Gaps
- No phone number visible in the detail
- No "last purchase" date visible in the detail
- No "total cash purchases" figure (cash sales, not just credit)
- No quick-action button "नया बिल बनाएं" (create bill for this customer)
- `Customer` model has `phone`, `lastPurchaseAt` fields but they're not displayed in detail screen

#### Implementation Strategy

**Enhanced header stats:**
```
[ उधार दिया ]  [ नकद खरीद ]  [ कुल मिला ]  [ बकाया ]
  ₹1,200         ₹800          ₹600          ₹600
```

**Profile sub-header (below stats, above ledger):**
```
📱 9876543210   |   📅 Last: 15 Aug 2026   |   [नया बिल बनाएं →]
```

**"नया बिल बनाएं" button:** Navigates to `VoiceBillingScreen` with the customer name pre-filled. This requires the billing screen to accept an optional `initialCustomerName` constructor parameter.

#### Files Affected
| File | Change |
|------|--------|
| `lib/screens/reports_screen.dart` | Add phone + lastPurchase to detail header; add total cash purchases stat; add "नया बिल" button |
| `lib/screens/voice_billing_screen.dart` | Accept `initialCustomerName` optional param |

#### Acceptance Criteria
- [ ] Phone number shown in customer detail (if set)
- [ ] Last purchase date shown
- [ ] "नया बिल बनाएं" button navigates to billing with customer pre-filled
- [ ] Total cash purchases (non-credit) shown as a separate stat

---

### C-05 · Edit Customer Details

**Priority:** P2  
**Status:** 🔴 Missing entirely

#### RCA
`AddCustomerScreen` is push-and-forget. No edit flow was designed. Supabase has the customer record with `id`, `name`, `phone`, `opening_balance` — all editable.

#### Implementation Strategy

**UI:** Reuse `AddCustomerScreen` with an optional `Customer? existing` parameter. If non-null, pre-fills fields and changes the save action to an UPDATE.

```dart
// add_customer_screen.dart
class AddCustomerScreen extends StatefulWidget {
  final Customer? existing;  // null = add new, non-null = edit
  const AddCustomerScreen({super.key, this.existing});
  // ...
}

Future<void> _save() async {
  if (existing != null) {
    await SupabaseService.updateCustomer(id: existing!.id, ...);
  } else {
    await SupabaseService.createCustomer(...);
  }
}
```

**Access point:** Three-dot menu (or edit icon) in the `_CustomerDetailScreen` app bar.

**Service method:**
```dart
static Future<void> updateCustomer({
  required String id,
  required String name,
  String? phone,
  required double openingBalance,
}) async {
  await _client.from('customers')
      .update({'name': name.trim(), 'phone': phone, 'opening_balance': openingBalance})
      .eq('id', id)
      .eq('user_id', _userId!);  // ownership filter mandatory
}
```

#### Constraints
- Cannot edit customer name if they have past bills (name is the join key between `customers` and `past_bills`). Either: (a) warn user and disallow name change if bills exist, or (b) cascade update — update all `past_bills.customer_name` in the same transaction (risky). **Decision: block name edit if bills exist; show message "नाम बदलने के लिए पहले सभी बिल हटाएं".**

#### Files Affected
| File | Change |
|------|--------|
| `lib/screens/add_customer_screen.dart` | Add `existing` param; pre-fill; UPDATE path |
| `lib/services/supabase_service.dart` | Add `updateCustomer()` |
| `lib/screens/reports_screen.dart` | Add edit icon/menu to `_CustomerDetailScreen` |

#### Acceptance Criteria
- [ ] Edit icon visible in customer detail screen
- [ ] Tapping edit opens pre-filled form
- [ ] Phone and opening balance can always be edited
- [ ] Name edit is blocked if customer has past bills (with clear message)
- [ ] Changes saved correctly with `.eq('user_id', ...)` filter

---

### C-06 · Delete Customer with Safety Checks

**Priority:** P2  
**Status:** 🔴 Missing entirely

#### RCA
No delete flow designed. Deletion requires careful guardrails — deleting a customer with outstanding balance would silently remove a debt record.

#### Safety Rules (non-negotiable)

1. **Block deletion if outstanding > 0** — customer still owes money. Show: "ग्राहक पर ₹X बकाया है। पहले हिसाब चुकाएं।"
2. **Warn (don't block) if customer has transaction history** — even if outstanding = 0, if they have past bills, confirm with a dialog.
3. **Deletion is soft by design** — consider marking as `deleted=true` in Supabase rather than hard DELETE, so historical bill records remain queryable. (Alternatively, hard delete customers row but leave `past_bills` intact — bills have `customer_name` as string, not a FK.)
4. **Cannot delete if credit balance < 0** — they have advance credit. Refund first.

#### Implementation Strategy

```dart
Future<void> _deleteCustomer() async {
  final outstanding = _outstanding;  // from running balance
  
  if (outstanding > 0) {
    // Block — show error, no dialog
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('₹${outstanding.toStringAsFixed(0)} बकाया है। पहले हिसाब चुकाएं।')));
    return;
  }
  if (outstanding < 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('ग्राहक का ₹${outstanding.abs().toStringAsFixed(0)} अग्रिम जमा है। पहले वापस करें।')));
    return;
  }
  
  // Warn if history exists
  if (_ledger.isNotEmpty) {
    final confirm = await _confirmDeleteDialog();
    if (confirm != true) return;
  }
  
  await SupabaseService.deleteCustomer(id: widget.customer.id);
  if (mounted) Navigator.pop(context);
}
```

**Service method:**
```dart
static Future<void> deleteCustomer({required String id}) async {
  await _client.from('customers')
      .delete()
      .eq('id', id)
      .eq('user_id', _userId!);  // ownership filter mandatory
}
```

**Past bills:** Left untouched. `past_bills.customer_name` is a string — historical records remain intact even after customer is deleted from the `customers` table.

#### Files Affected
| File | Change |
|------|--------|
| `lib/services/supabase_service.dart` | Add `deleteCustomer()` |
| `lib/screens/reports_screen.dart` | Add delete option in `_CustomerDetailScreen` with safety gate |

#### Acceptance Criteria
- [ ] Delete option in customer detail screen (three-dot menu or swipe-to-delete on list)
- [ ] If outstanding > 0: blocked with message, no dialog shown
- [ ] If outstanding < 0 (advance credit): blocked with message
- [ ] If outstanding == 0 but has history: confirmation dialog shown
- [ ] If outstanding == 0 and no history: deleted directly
- [ ] After delete: customer removed from list; past bills unaffected

---

## Part C — Form Validation + UX Fixes

---

### V-01 · Inline Real-Time Form Validation (All Forms)

**Priority:** P2  
**Status:** 🔴 Currently submit-only validation

#### Affected Fields and Rules

| Field | Location | Rule | Blocker or Warning |
|-------|----------|------|-------------------|
| Customer name | `add_customer_screen` | Letters only (Hindi/Latin), spaces, dots, hyphens. Min 2 chars. No digits. | Blocker — digit characters filtered out instantly via `inputFormatters` |
| Phone number | `add_customer_screen` | Exactly 10 digits, numeric only | Warning shown after blur |
| Opening balance | `add_customer_screen` | Positive number, no negatives (direction handled by radio) | Warning shown after blur |
| Bill discount | `voice_billing_screen` | Cannot exceed subtotal | Warning shown in real-time |
| Amount in ledger dialog | `reports_screen` | Positive, non-zero, numeric | Warning shown after value is entered |

#### Implementation Pattern (for all fields)

```dart
// State
String? _nameError;

// TextField
TextFormField(
  controller: _nameCtrl,
  inputFormatters: [
    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Zऀ-ॿ\s\.\-]')),
  ],
  onChanged: (v) => setState(() {
    _nameError = v.trim().length < 2 ? 'कम से कम 2 अक्षर चाहिए' : null;
  }),
  decoration: InputDecoration(
    hintText: 'जैसे: Ramesh Kumar',
    errorText: _nameError,  // shown inline, below field
    errorStyle: const TextStyle(color: Colors.red, fontSize: 11),
  ),
)
```

No `GlobalKey<FormState>` needed for these — local state replaces `validator:`. The submit button checks all error strings are null before proceeding.

#### Files Affected
| File | Change |
|------|--------|
| `lib/screens/add_customer_screen.dart` | Replace `validator:` with `onChanged:` + local error state |
| `lib/screens/reports_screen.dart` | Add amount validation in ledger entry dialog |

---

### I-01 · Inventory Category + Unit Dropdowns

**Priority:** P2  
**Status:** 🔴 Free-text TextFields today

#### RCA
Category and Unit were implemented as plain `TextField` for speed. Free text leads to inconsistency ("अनाज" vs "Anaj" vs "anaj"), making filtering and grouping impossible.

#### Predefined Lists

**Categories (श्रेणी):**
`अनाज | दाल | तेल | मसाले | शक्कर / नमक | आटा | चावल | पेय पदार्थ | साबुन / सफाई | डेयरी | अन्य`

**Units (इकाई):**
`किलो | ग्राम | लिटर | मिलीलिटर | पैकेट | पीस | दर्जन | बोरी | थैली | अन्य`

#### Implementation Strategy

Replace both `TextField` widgets in the inventory add form with `DropdownButtonFormField`:

```dart
DropdownButtonFormField<String>(
  value: _selectedCategory,
  items: _kCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
  onChanged: (v) => setState(() => _selectedCategory = v),
  decoration: const InputDecoration(
    labelText: 'श्रेणी',
    isDense: true,
  ),
),
```

When "अन्य" is selected, show an additional `TextField` for custom entry (stored as-is).

The existing `_categoryCtrl` and `_unitCtrl` controllers can be replaced with `String? _selectedCategory` and `String? _selectedUnit` state vars.

**Existing inventory items:** Already stored as strings. No migration needed — the dropdown will show existing strings if they match; otherwise fall back to "अन्य" + free text field.

#### Files Affected
| File | Change |
|------|--------|
| `lib/screens/inventory_screen.dart` | Replace category + unit `TextField` with `DropdownButtonFormField`; add "अन्य" free-text path |

#### Acceptance Criteria
- [ ] Category field shows a dropdown with Hindi category list
- [ ] Unit field shows a dropdown with Hindi unit list
- [ ] Selecting "अन्य" in either dropdown reveals a free-text field
- [ ] Selected values saved correctly to DB
- [ ] Existing inventory items with non-standard strings are not broken

---

## Implementation Order — Complete Priority Queue

```
Phase 1 (Bug fixes — current Sprint 11):
  [1] F-01  PDF Devanagari fix            ← P1, start immediately on approval
  [2] F-02  Stats payment filter          ← P1, 1-line, fast follow
  [3] F-03  WhatsApp share PDF            ← P2, depends on F-01

Phase 2 (Foundation — must be done before C-02+):
  [4] V-01  Inline form validation         ← Foundational UX, affects all forms
  [5] C-01  Customer creation UX           ← Enhanced opening balance + validation

Phase 3 (Customer CRM):
  [6] C-02  Cash loan transaction type     ← Needs backend VALID_TX_TYPES update
  [7] C-03  Unified customer ledger        ← Depends on C-02 type being in place
  [8] C-04  Customer profile view          ← Enhancement on top of ledger
  [9] C-05  Edit customer                  ← Standalone
  [10] C-06 Delete customer (with checks)  ← Standalone

Phase 4 (Inventory + optional UX):
  [11] I-01  Category + unit dropdowns
  [12] UX-01 Voice vs Manual mode selector
  [13] UX-02 Outstanding vs advance credit split on home card
```

---

## Non-Negotiable Rules

1. **No commit or push** without explicit "commit this" / "push this" from user
2. **No new files created** without showing content first and getting approval
3. **One feature at a time** — fully approved + verified before the next starts
4. **Every DB write** includes `.eq("user_id", ...)` ownership filter
5. **Stock validation** stays on Flutter review screen only — never in `main.py`
6. **API_SECRET** = `smartdukan_2024_secret` — never committed
7. **Customer name is the join key** — name edits blocked if past bills exist (C-05 rule)
8. **Deletion safety gate** — outstanding ≠ 0 → hard block, no dialog (C-06 rule)
