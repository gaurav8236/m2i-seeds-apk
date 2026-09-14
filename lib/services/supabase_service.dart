import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../supabase_config.dart';
import 'auth_service.dart';

enum StatsPeriod { today, thisWeek, thisMonth, custom }

// Bug fix (Sprint 7): /voice-checkout/ can return HTTP 200 with
// {"status": "partial", "oversold": [...]}  when an item's requested
// quantity exceeds what's actually in stock — nothing was saved in that
// case (see checkout_and_apply_balance() in
// mobile/migrations/sprint7_002_checkout_rpc.sql). Before this fix,
// callers only checked response.statusCode != 200, so a partial/oversold
// response looked like a full success to the shopkeeper. This exception
// carries the oversold detail so the UI can show it.
class CheckoutOversoldException implements Exception {
  final String message;
  final List<Map<String, dynamic>> oversold;
  CheckoutOversoldException(this.message, this.oversold);
  @override
  String toString() => message;
}

class SupabaseService {
  static final _client = Supabase.instance.client;

  static String? get _userId => AuthService.userId;

  // ── Stock ──────────────────────────────────────────────────────────────────

  static Future<List<StockItem>> fetchStock() async {
    final userId = _userId;
    if (userId == null) return [];

    final res = await _client
        .from('user_stock')
        .select(
            'id, current_stock, selling_price, low_stock_limit, aliases, master_inventory(item_name, category, unit)')
        .eq('user_id', userId);

    return (res as List).map((e) => StockItem.fromMap(e)).toList();
  }

  static Future<List<MasterItem>> fetchMasterInventory() async {
    final res = await _client
        .from('master_inventory')
        .select('id, item_name, category, unit');
    return (res as List).map((e) => MasterItem.fromMap(e)).toList();
  }

  static Future<void> upsertInventoryItems(
      List<Map<String, dynamic>> items) async {
    final userId = _userId;
    if (userId == null) return;

    await _client.rpc('upsert_inventory_item', params: {
      'p_user_id': userId,
      'p_items': items,
    });
  }

  // Direct update for an EXISTING item by its user_stock.id.
  // Unlike upsertInventoryItems (which uses item_name as the upsert key and
  // creates a new item when the name changes — bug #22), this path updates
  // both user_stock and master_inventory directly via ID, so renaming works
  // correctly (#22) and stock-only edits no longer fail (#20).
  static Future<void> updateInventoryItem({
    required String stockId,
    required String itemName,
    required String category,
    required String unit,
    required double sellingPrice,
    required double currentStock,
    required double lowStockLimit,
    required List<String> aliases,
  }) async {
    final userId = _userId;
    if (userId == null) throw Exception('Not authenticated');

    // 1. Update the user-specific stock columns.
    await _client
        .from('user_stock')
        .update({
          'selling_price': sellingPrice,
          'current_stock': currentStock,
          'low_stock_limit': lowStockLimit,
          'aliases': aliases,
        })
        .eq('id', stockId)
        .eq('user_id', userId);

    // 2. Fetch the product_id FK to master_inventory.
    final row = await _client
        .from('user_stock')
        .select('product_id')
        .eq('id', stockId)
        .eq('user_id', userId)
        .single();

    final productId = row['product_id']?.toString();
    if (productId != null && productId.isNotEmpty) {
      await _client.from('master_inventory').update({
        'item_name': itemName.trim(),
        'category': category.trim(),
        'unit': unit.trim(),
      }).eq('id', productId);
    }
  }

  // ── Bills ──────────────────────────────────────────────────────────────────

  static Future<List<Bill>> fetchPastBills() async {
    final userId = _userId;
    if (userId == null) return [];

    final res = await _client
        .from('past_bills')
        .select('*')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (res as List).map((e) => Bill.fromMap(e)).toList();
  }

  static Future<List<String>> fetchCustomerNames() async {
    final userId = _userId;
    if (userId == null) return [];

    // Case-insensitive dedup across both sources (bug #58).
    // Seen set uses lowercased key; first-seen casing is kept for display.
    final seen = <String>{};
    final names = <String>[];

    void addName(String? raw) {
      final name = raw?.trim() ?? '';
      if (name.isEmpty) return;
      final key = name.toLowerCase();
      if (seen.add(key)) names.add(name);
    }

    // Primary source: customers table (includes zero-bill customers — fixes #46 incomplete).
    try {
      final custRes = await _client
          .from('customers')
          .select('name')
          .eq('user_id', userId)
          .order('name');
      for (final e in (custRes as List)) {
        addName(e['name']?.toString());
      }
    } catch (_) {
      // customers table unavailable — fall through to past_bills.
    }

    // Secondary source: past_bills (catches names for customers not in customers table).
    try {
      final billRes = await _client
          .from('past_bills')
          .select('customer_name')
          .eq('user_id', userId)
          .not('customer_name', 'is', null);
      for (final e in (billRes as List)) {
        addName(e['customer_name']?.toString());
      }
    } catch (_) {
      // past_bills unavailable — return whatever customers table gave us.
    }

    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  // ── Checkout ───────────────────────────────────────────────────────────────

  // Shared response handling for every /voice-checkout/ caller (checkout,
  // recordPayment, recordDeposit). Bug fix (Sprint 7): the endpoint returns
  // HTTP 200 even for {"status": "partial", ...} (oversold, nothing saved)
  // — checking only statusCode silently treated that as success.
  static void _checkCheckoutResponse(http.Response response, String failureLabel) {
    if (response.statusCode != 200) {
      throw Exception('$failureLabel: ${response.statusCode}');
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      // Unparseable body on a 200 — treat as success rather than block the
      // user on a response-shape issue unrelated to whether the write happened.
      return;
    }
    if (body['status'] == 'partial') {
      final oversold = (body['oversold'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      throw CheckoutOversoldException(
        body['message']?.toString() ?? '$failureLabel: कुछ सामान का स्टॉक पर्याप्त नहीं था',
        oversold,
      );
    }
  }

  static Future<void> checkout({
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    required double discountAmount,
    String? customerName,
    required bool isCredit,
    double nagadAmount = 0,
  }) async {
    final userId = _userId;
    if (userId == null) throw Exception('Not authenticated');

    if (customerName != null && customerName.trim().isNotEmpty) {
      await ensureCustomerExists(customerName);
    }

    final response = await http.post(
      Uri.parse('${SupabaseConfig.railwayBaseUrl}/voice-checkout/'),
      headers: {
        'Content-Type': 'application/json',
        'X-Api-Key': SupabaseConfig.apiSecret
      },
      body: jsonEncode({
        'user_id': userId,
        'total_bill_amount': totalAmount,
        'discount_amount': discountAmount,
        'customer_name': customerName,
        'is_credit': isCredit,
        'nagad_amount': nagadAmount,
        'items': items,
      }),
    );

    _checkCheckoutResponse(response, 'Checkout failed');
  }

  // ── Stats ──────────────────────────────────────────────────────────────────

  static Future<Map<String, double>> fetchMonthStats() async {
    final now = DateTime.now();
    return fetchFilteredStats(
      from: DateTime(now.year, now.month, 1),
      to: now,
    );
  }

  static Future<Map<String, double>> fetchFilteredStats({
    required DateTime from,
    required DateTime to,
  }) async {
    final userId = _userId;
    if (userId == null) return {'credit': 0, 'paid': 0};

    final res = await _client
        .from('past_bills')
        .select('total_amount, is_credit, nagad_amount, transaction_type')
        .eq('user_id', userId)
        // Always compare in UTC — Supabase stores created_at in UTC.
        // Without .toUtc() a local DateTime (e.g. IST midnight) is sent as-is
        // and Supabase treats it as UTC, shifting the filter by 5h30m for IST users.
        .gte('created_at', from.toUtc().toIso8601String())
        .lte('created_at', to.toUtc().toIso8601String())
        // Exclude payment receipts, deposits and cash loans — they are not sales.
        // Use OR to preserve pre-Sprint-3 rows where transaction_type IS NULL
        // (SQL NOT IN silently drops NULLs because NULL NOT IN (...) = NULL).
        .or('transaction_type.is.null,transaction_type.not.in.(payment,deposit,cash_loan)');

    return bucketFilteredStats(res as List);
  }

  // Pure bucketing logic extracted from fetchFilteredStats() (BUG-12) so it
  // can be unit-tested without a Supabase mock — takes the raw rows already
  // fetched from `past_bills` and returns the same {'credit', 'paid'} shape.
  // Mirrors the split-bill decomposition _computeRunningBalances()/
  // _totalCreditGiven/_totalReceived (reports_screen.dart) already do
  // correctly on the per-customer screen (the BUG-7 fix): a split bill's
  // nagad_amount (cash) portion counts toward 'paid', and its remaining
  // (total_amount − nagad_amount) udhar portion counts toward 'credit' —
  // instead of the previous behavior of dumping the split's FULL
  // total_amount into 'paid' and never touching 'credit' at all.
  @visibleForTesting
  static Map<String, double> bucketFilteredStats(List<dynamic> res) {
    double credit = 0, paid = 0;
    for (final bill in res) {
      final amount = (bill['total_amount'] as num?)?.toDouble() ?? 0;
      final nagad = (bill['nagad_amount'] as num?)?.toDouble() ?? 0;
      // Resolve type — prefer transaction_type; fall back to is_credit for old rows.
      final txType = bill['transaction_type']?.toString();
      final resolvedType = (txType != null && txType.isNotEmpty)
          ? txType
          : (bill['is_credit'] == true ? 'credit' : 'sale');
      if (resolvedType == 'credit') {
        credit += amount;
      } else if (resolvedType == 'split') {
        paid += nagad;
        credit += (amount - nagad).clamp(0, double.infinity);
      } else {
        // 'sale' and 'payment' both represent cash received in the period.
        paid += amount;
      }
    }
    return {'credit': credit, 'paid': paid};
  }

  // Total unpaid उधार across ALL customers — not period-filtered.
  //
  // Perf (Sprint 7, P2-c): previously walked a shop's ENTIRE past_bills
  // history on every call (O(bill count), even after the 2026-09-13 dedupe
  // that removed the redundant duplicate fetch but not the underlying
  // per-load cost). Now reads the server-maintained running_balance column
  // directly — O(customer count) — see
  // mobile/migrations/sprint7_001_customer_running_balance.sql and
  // sprint7_002_checkout_rpc.sql (which keeps running_balance current on
  // every checkout). Uses per-customer clamping (not a single aggregate
  // clamp) so that an overpayment by Customer A never cancels Customer B's
  // outstanding (#48) — same semantics as before, just computed server-side
  // incrementally instead of client-side from scratch each load.
  static Future<double> fetchTotalOutstanding() async {
    final userId = _userId;
    if (userId == null) return 0;

    final custRes = await _client
        .from('customers')
        .select('opening_balance, running_balance')
        .eq('user_id', userId);

    double total = 0;
    for (final c in (custRes as List)) {
      final opening = (c['opening_balance'] as num?)?.toDouble() ?? 0;
      final running = (c['running_balance'] as num?)?.toDouble() ?? 0;
      total += (opening + running).clamp(0.0, double.infinity);
    }
    return total;
  }

  // ── Customers ──────────────────────────────────────────────────────────────

  // Perf (Sprint 7, P2-c): previously walked a shop's ENTIRE past_bills
  // history to aggregate credit/paid per customer on every call — now reads
  // running_balance directly (see fetchTotalOutstanding()'s note above).
  // No per-customer clamp here — negative = customer has a credit balance
  // (advance deposit / overpayment), matching pre-Sprint-7 semantics exactly.
  static Future<List<Customer>> fetchCustomers() async {
    final userId = _userId;
    if (userId == null) return [];

    final custRes = await _client
        .from('customers')
        .select('*')
        .eq('user_id', userId)
        .order('name');

    final customers = (custRes as List).map((c) {
      final customer = Customer.fromMap(c);
      customer.outstanding = customer.openingBalance + customer.runningBalance;
      return customer;
    }).toList();

    // Sort: outstanding-first (highest due at top), then alphabetical
    customers.sort((a, b) {
      if (b.outstanding != a.outstanding) {
        return b.outstanding.compareTo(a.outstanding);
      }
      return a.name.compareTo(b.name);
    });

    return customers;
  }

  static Future<void> createCustomer({
    required String name,
    String? phone,
    double openingBalance = 0,
  }) async {
    final userId = _userId;
    if (userId == null) throw Exception('Not authenticated');
    await _client.from('customers').insert({
      'user_id': userId,
      'name': name.trim(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      'opening_balance': openingBalance,
    });
  }

  // C-05: update phone / opening_balance. Name edits are blocked at the UI
  // layer if the customer has any past bills.
  static Future<void> updateCustomer({
    required String id,
    String? phone, // pass '' to clear, null to leave unchanged
    double? openingBalance,
  }) async {
    final userId = _userId;
    if (userId == null) throw Exception('Not authenticated');
    final updates = <String, dynamic>{};
    if (phone != null) updates['phone'] = phone.isEmpty ? null : phone;
    if (openingBalance != null) updates['opening_balance'] = openingBalance;
    if (updates.isEmpty) return;
    await _client
        .from('customers')
        .update(updates)
        .eq('id', id)
        .eq('user_id', userId);
  }

  // C-06: hard-delete. Caller MUST verify outstanding == 0 before calling.
  static Future<void> deleteCustomer(String id) async {
    final userId = _userId;
    if (userId == null) throw Exception('Not authenticated');
    await _client.from('customers').delete().eq('id', id).eq('user_id', userId);
  }

  // Called before checkout to ensure customer exists in the customers table.
  // Uses case-insensitive lookup first to avoid creating "Mayank"/"mayank"
  // duplicates (#58).
  static Future<void> ensureCustomerExists(String customerName) async {
    final userId = _userId;
    if (userId == null) return;
    final normalized = customerName.trim();
    try {
      final existing = await _client
          .from('customers')
          .select('id')
          .eq('user_id', userId)
          .ilike('name', normalized)
          .maybeSingle();
      if (existing == null) {
        await _client.from('customers').insert({
          'user_id': userId,
          'name': normalized,
        });
      }
      // If a case-variant already exists, don't create a duplicate.
    } catch (_) {
      // Non-fatal — checkout can proceed even if customer row is missing.
    }
  }

  // ── Customer Ledger ────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchCustomerLedger(
      String customerName) async {
    final userId = _userId;
    if (userId == null) return [];

    // ilike = case-insensitive match — fixes "Mayank"/"mayank" split (#58).
    final res = await _client
        .from('past_bills')
        .select(
            'total_amount, is_credit, nagad_amount, transaction_type, created_at')
        .eq('user_id', userId)
        .ilike('customer_name', customerName.trim())
        .order('created_at',
            ascending:
                true); // ascending: running-balance computation needs oldest-first

    return (res as List).map((bill) {
      final txType = bill['transaction_type']?.toString();
      final nagad = (bill['nagad_amount'] as num?)?.toDouble() ?? 0;
      // transaction_type is authoritative (covers 'deposit' too); fall back to
      // is_credit/nagad only for old rows written before that column existed.
      final resolvedType = (txType != null && txType.isNotEmpty)
          ? txType
          : (bill['is_credit'] == true
              ? (nagad > 0 ? 'split' : 'credit')
              : 'sale');
      return {
        'type': resolvedType,
        'amount': (bill['total_amount'] as num?)?.toDouble() ?? 0,
        'nagad_amount': nagad,
        // Keep raw string; .toLocal() applied at display site via DateTime.parse.
        'created_at': bill['created_at']?.toString(),
      };
    }).toList();
  }

  // Server-filtered bill history for a single customer — mirrors
  // fetchCustomerLedger's .ilike('customer_name', ...) pattern above, but
  // returns full Bill objects (like fetchPastBills()) for the "बिल इतिहास"
  // list on the customer-detail screen. Replaces the old pattern of calling
  // fetchPastBills() (whole shop, unfiltered) and filtering client-side.
  static Future<List<Bill>> fetchCustomerBills(String customerName) async {
    final userId = _userId;
    if (userId == null) return [];

    final res = await _client
        .from('past_bills')
        .select('*')
        .eq('user_id', userId)
        .ilike('customer_name', customerName.trim())
        .order('created_at', ascending: false);

    return (res as List).map((e) => Bill.fromMap(e)).toList();
  }

  static Future<void> recordPayment({
    required String customerName,
    required double amount,
  }) async {
    final userId = _userId;
    if (userId == null) throw Exception('Not authenticated');

    if (customerName.trim().isNotEmpty) {
      await ensureCustomerExists(customerName);
    }

    final response = await http.post(
      Uri.parse('${SupabaseConfig.railwayBaseUrl}/voice-checkout/'),
      headers: {
        'Content-Type': 'application/json',
        'X-Api-Key': SupabaseConfig.apiSecret
      },
      body: jsonEncode({
        'user_id': userId,
        'total_bill_amount': amount,
        'discount_amount': 0,
        'customer_name': customerName,
        'is_credit': false,
        // Explicit type so the backend doesn't derive 'sale' from is_credit=false.
        'transaction_type': 'payment',
        'items': [
          {
            'stock_id': null,
            'new_stock': null,
            'item_name': 'भुगतान (Payment Received)',
            'quantity_billed': 1,
            'price_per_unit': amount,
            'item_total': amount,
            'error': false,
          }
        ],
      }),
    );

    _checkCheckoutResponse(response, 'Payment failed');
  }

  // Record an advance deposit — customer pays in ahead of any bill.
  // Stored as transaction_type='deposit', is_credit=false.
  // Reduces outstanding; if it exceeds balance, outstanding goes negative (credit).
  static Future<void> recordDeposit({
    required String customerName,
    required double amount,
  }) async {
    final userId = _userId;
    if (userId == null) throw Exception('Not authenticated');

    if (customerName.trim().isNotEmpty) {
      await ensureCustomerExists(customerName);
    }

    final response = await http.post(
      Uri.parse('${SupabaseConfig.railwayBaseUrl}/voice-checkout/'),
      headers: {
        'Content-Type': 'application/json',
        'X-Api-Key': SupabaseConfig.apiSecret
      },
      body: jsonEncode({
        'user_id': userId,
        'total_bill_amount': amount,
        'discount_amount': 0,
        'customer_name': customerName,
        'is_credit': false,
        'transaction_type': 'deposit',
        'items': [
          {
            'stock_id': null,
            'new_stock': null,
            'item_name': 'अग्रिम जमा (Advance Deposit)',
            'quantity_billed': 1,
            'price_per_unit': amount,
            'item_total': amount,
            'error': false,
          }
        ],
      }),
    );

    _checkCheckoutResponse(response, 'Deposit failed');
  }

  // ── Stock History ───────────────────────────────────────────────────────────

  static Future<void> logRestock({
    required String stockId,
    required double quantityBefore,
    required double quantityAfter,
  }) async {
    final userId = _userId;
    if (userId == null) return;
    await _client.from('stock_history').insert({
      'user_id': userId,
      'stock_id': stockId,
      'quantity_before': quantityBefore,
      'quantity_after': quantityAfter,
      'event_type': 'restock',
    });
  }

  static Future<StockHistoryEntry?> fetchLastRestock(String stockId) async {
    final userId = _userId;
    if (userId == null) return null;
    final res = await _client
        .from('stock_history')
        .select('*')
        .eq('stock_id', stockId)
        .eq('user_id', userId)
        .eq('event_type', 'restock')
        .order('created_at', ascending: false)
        .limit(1);

    if ((res as List).isEmpty) return null;
    return StockHistoryEntry.fromMap(res.first);
  }

  // Units of a stock item sold this calendar month — scanned from bill_details
  // Returns true if a customer with [name] (case-insensitive) already exists
  // for this user, ignoring the customer with [excludeId] (for rename check #41).
  static Future<bool> checkCustomerNameExists(String name,
      {String? excludeId}) async {
    final userId = _userId;
    if (userId == null) return false;
    // ilike = case-insensitive — catches "Ram" / "ram" / "RAM" as the same name.
    // excludeId filters out the customer being renamed so a no-op rename passes.
    final res = await _client
        .from('customers')
        .select('id')
        .eq('user_id', userId)
        .ilike('name', name.trim());
    if (excludeId == null) return (res as List).isNotEmpty;
    return (res as List).any((row) => row['id']?.toString() != excludeId);
  }

  // Returns true if another user_stock item (different id) already has [name]
  // (case-insensitive) for this user — used to prevent duplicate items (#32).
  static Future<bool> checkItemNameExists(String name,
      {required String excludeStockId}) async {
    final userId = _userId;
    if (userId == null) return false;
    final res = await _client
        .from('user_stock')
        .select('id, master_inventory!inner(item_name)')
        .eq('user_id', userId);
    final nameLower = name.trim().toLowerCase();
    return (res as List).any((row) {
      if (row['id']?.toString() == excludeStockId) return false;
      final itemName = row['master_inventory']?['item_name']?.toString() ?? '';
      return itemName.trim().toLowerCase() == nameLower;
    });
  }

  // [itemName] is optional and used as a fallback when stock_id in bill_details
  // references a now-stale row (bills created before Sprint 5's ID-stabilisation fix).
  static Future<double> fetchItemSalesThisMonth(
    String stockId, {
    String? itemName,
  }) async {
    final userId = _userId;
    if (userId == null) return 0;

    final now = DateTime.now();
    // DateTime(y, m, 1) is local (IST) midnight → .toUtc() is the correct
    // IST boundary in UTC (e.g. "2024-12-31T18:30:00Z" = Jan 1 IST midnight).
    final firstDay = DateTime(now.year, now.month, 1).toUtc().toIso8601String();
    // Upper bound: first of next month; DateTime handles month-13 overflow. (#19)
    final monthEnd =
        DateTime(now.year, now.month + 1, 1).toUtc().toIso8601String();

    final res = await _client
        .from('past_bills')
        .select('bill_details')
        .eq('user_id', userId)
        .gte('created_at', firstDay)
        .lt('created_at', monthEnd); // defensive upper bound (#19)

    final nameLower = itemName?.trim().toLowerCase();
    double totalQty = 0;
    for (final bill in (res as List)) {
      final details =
          List<Map<String, dynamic>>.from(bill['bill_details'] ?? []);
      for (final item in details) {
        final matchById = item['stock_id']?.toString() == stockId;
        // Fallback: match by item_name for pre-S5 bills where stock_id was
        // stale after the old name-keyed upsert RPC duplicated items (#19).
        final matchByName = nameLower != null &&
            item['item_name']?.toString().trim().toLowerCase() == nameLower;
        if (matchById || matchByName) {
          totalQty += (item['quantity_billed'] as num?)?.toDouble() ?? 0;
        }
      }
    }
    return totalQty;
  }
}
