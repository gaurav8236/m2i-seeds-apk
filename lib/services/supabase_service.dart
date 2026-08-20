import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../supabase_config.dart';
import 'auth_service.dart';

enum StatsPeriod { today, thisWeek, thisMonth, custom }

class SupabaseService {
  static final _client = Supabase.instance.client;

  static String? get _userId => AuthService.userId;

  // ── Stock ──────────────────────────────────────────────────────────────────

  static Future<List<StockItem>> fetchStock() async {
    final userId = _userId;
    if (userId == null) return [];

    final res = await _client
        .from('user_stock')
        .select('id, current_stock, selling_price, low_stock_limit, aliases, master_inventory(item_name, category, unit)')
        .eq('user_id', userId);

    return (res as List).map((e) => StockItem.fromMap(e)).toList();
  }

  static Future<List<MasterItem>> fetchMasterInventory() async {
    final res = await _client
        .from('master_inventory')
        .select('id, item_name, category, unit');
    return (res as List).map((e) => MasterItem.fromMap(e)).toList();
  }

  static Future<void> upsertInventoryItems(List<Map<String, dynamic>> items) async {
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
      await _client
          .from('master_inventory')
          .update({
            'item_name': itemName.trim(),
            'category': category.trim(),
            'unit': unit.trim(),
          })
          .eq('id', productId);
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
      headers: {'Content-Type': 'application/json', 'X-Api-Key': SupabaseConfig.apiSecret},
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

    if (response.statusCode != 200) {
      throw Exception('Checkout failed: ${response.statusCode}');
    }
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
        .select('total_amount, is_credit, transaction_type')
        .eq('user_id', userId)
        .gte('created_at', from.toUtc().toIso8601String())
        .lte('created_at', to.toUtc().toIso8601String())
        // Exclude payment receipts, deposits and cash loans — they are not sales.
        // Use OR to preserve pre-Sprint-3 rows where transaction_type IS NULL
        // (SQL NOT IN silently drops NULLs because NULL NOT IN (...) = NULL).
        .or('transaction_type.is.null,transaction_type.not.in.(payment,deposit,cash_loan)');

    double credit = 0, paid = 0;
    for (final bill in (res as List)) {
      final amount = (bill['total_amount'] as num?)?.toDouble() ?? 0;
      // Resolve type — prefer transaction_type; fall back to is_credit for old rows.
      final txType = bill['transaction_type']?.toString();
      final resolvedType = (txType != null && txType.isNotEmpty)
          ? txType
          : (bill['is_credit'] == true ? 'credit' : 'sale');
      if (resolvedType == 'credit') {
        credit += amount;
      } else {
        // 'sale' and 'payment' both represent cash received in the period.
        paid += amount;
      }
    }
    return {'credit': credit, 'paid': paid};
  }

  // Total unpaid उधार across ALL customers — not period-filtered.
  // Includes customers.opening_balance so customers with pre-existing debt but
  // no bills are counted correctly on the dashboard KPI.
  //
  // Uses per-customer clamping (not a single aggregate clamp) so that an
  // overpayment by Customer A never cancels Customer B's outstanding (#48).
  static Future<double> fetchTotalOutstanding() async {
    final userId = _userId;
    if (userId == null) return 0;

    // Aggregate credits and payments per customer name (case-insensitive key).
    final Map<String, double> perCust = {};

    // Bills — primary source, must succeed.
    final billRes = await _client
        .from('past_bills')
        .select('customer_name, total_amount, is_credit, transaction_type, nagad_amount')
        .eq('user_id', userId)
        .not('customer_name', 'is', null);
    for (final bill in (billRes as List)) {
      final custName = bill['customer_name']?.toString().trim() ?? '';
      if (custName.isEmpty) continue;
      final key = custName.toLowerCase();
      perCust.putIfAbsent(key, () => 0.0);
      final amount = (bill['total_amount'] as num?)?.toDouble() ?? 0;
      final txType = bill['transaction_type']?.toString();
      final resolvedType = (txType != null && txType.isNotEmpty)
          ? txType
          : (bill['is_credit'] == true ? 'credit' : 'sale');
      final nagad = (bill['nagad_amount'] as num?)?.toDouble() ?? 0;
      if (resolvedType == 'credit') {
        perCust[key] = perCust[key]! + amount;
      } else if (resolvedType == 'split') {
        perCust[key] = perCust[key]! + (amount - nagad).clamp(0, double.infinity);
      } else if (resolvedType == 'payment') {
        perCust[key] = perCust[key]! - amount;
      }
      // 'sale' is settled at point-of-sale — neutral for outstanding.
    }

    // Opening balances — secondary; if this query fails, bills-only total is
    // still valid and surfaced rather than crashing the dashboard KPI.
    try {
      final custRes = await _client
          .from('customers')
          .select('name, opening_balance')
          .eq('user_id', userId);
      for (final c in (custRes as List)) {
        final custName = c['name']?.toString().trim() ?? '';
        if (custName.isEmpty) continue;
        final key = custName.toLowerCase();
        perCust.putIfAbsent(key, () => 0.0);
        perCust[key] = perCust[key]! +
            ((c['opening_balance'] as num?)?.toDouble() ?? 0);
      }
    } catch (_) {
      // Customers table unavailable (RLS / network) — bills total is still valid.
    }

    // Sum with per-customer clamp so Customer A's overpayment cannot reduce
    // Customer B's outstanding in the KPI (#48).
    return perCust.values
        .fold<double>(0.0, (sum, v) => sum + v.clamp(0.0, double.infinity));
  }

  // ── Customers ──────────────────────────────────────────────────────────────

  static Future<List<Customer>> fetchCustomers() async {
    final userId = _userId;
    if (userId == null) return [];

    final custRes = await _client
        .from('customers')
        .select('*')
        .eq('user_id', userId)
        .order('name');

    final billRes = await _client
        .from('past_bills')
        .select('customer_name, total_amount, is_credit, transaction_type, nagad_amount, created_at')
        .eq('user_id', userId)
        .not('customer_name', 'is', null);

    // Aggregate bill amounts + last activity date per customer name.
    // Key is lowercased + trimmed — case-insensitive dedup (bug #58).
    // Outstanding logic:
    //   'credit'  → customer owes money  (adds to outstanding)
    //   'payment' → customer paid        (subtracts from outstanding)
    //   'sale'    → cash at point-of-sale (neutral — already settled)
    final Map<String, Map<String, dynamic>> agg = {};
    for (final bill in (billRes as List)) {
      final name = bill['customer_name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      agg.putIfAbsent(key, () => {'credit': 0.0, 'paid': 0.0, 'lastDate': null});
      final amt = (bill['total_amount'] as num?)?.toDouble() ?? 0;
      final txType = bill['transaction_type']?.toString();
      final resolvedType = (txType != null && txType.isNotEmpty)
          ? txType
          : (bill['is_credit'] == true ? 'credit' : 'sale');
      final nagad = (bill['nagad_amount'] as num?)?.toDouble() ?? 0;
      if (resolvedType == 'credit') {
        agg[key]!['credit'] = (agg[key]!['credit'] as double) + amt;
      } else if (resolvedType == 'split') {
        // Split bill: only (total - nagad) is still owed.
        agg[key]!['credit'] = (agg[key]!['credit'] as double) + (amt - nagad).clamp(0, double.infinity);
      } else if (resolvedType == 'payment') {
        agg[key]!['paid'] = (agg[key]!['paid'] as double) + amt;
      }
      // 'sale' is neutral — no outstanding impact.
      final date = DateTime.tryParse(bill['created_at'] as String? ?? '');
      final existing = agg[key]!['lastDate'] as DateTime?;
      if (date != null && (existing == null || date.isAfter(existing))) {
        agg[key]!['lastDate'] = date;
      }
    }

    final customers = (custRes as List).map((c) {
      final customer = Customer.fromMap(c);
      final data = agg[customer.name.trim().toLowerCase()];
      if (data != null) {
        final credit = data['credit'] as double;
        final paid = data['paid'] as double;
        // Allow negative: customer has a credit balance (advance deposit / overpayment)
        customer.outstanding = customer.openingBalance + credit - paid;
        customer.lastPurchaseAt = data['lastDate'] as DateTime?;
      } else {
        customer.outstanding = customer.openingBalance;
      }
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

  static Future<void> updateCustomer({
    required String id,
    required String oldName,   // needed to cascade rename to past_bills (#52)
    required String name,
    String? phone,
    required double openingBalance,
  }) async {
    final userId = _userId;
    if (userId == null) throw Exception('Not authenticated');
    final newName = name.trim();
    await _client
        .from('customers')
        .update({
          'name': newName,
          'phone': phone != null && phone.trim().isNotEmpty ? phone.trim() : null,
          'opening_balance': openingBalance,
        })
        .eq('id', id)
        .eq('user_id', userId);

    // Cascade rename to past_bills so ledger history stays intact after a
    // customer name change (#52).
    if (newName != oldName.trim()) {
      await _client
          .from('past_bills')
          .update({'customer_name': newName})
          .eq('user_id', userId)
          .eq('customer_name', oldName.trim());
    }
  }

  // ── Customer Ledger ────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchCustomerLedger(String customerName) async {
    final userId = _userId;
    if (userId == null) return [];

    // ilike = case-insensitive match — fixes "Mayank"/"mayank" split (#58).
    final res = await _client
        .from('past_bills')
        .select('total_amount, is_credit, nagad_amount, transaction_type, created_at')
        .eq('user_id', userId)
        .ilike('customer_name', customerName.trim())
        .order('created_at', ascending: true); // ascending: running-balance computation needs oldest-first

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

  static Future<void> recordPayment({
    required String customerName,
    required double amount,
  }) async {
    final userId = _userId;
    if (userId == null) throw Exception('Not authenticated');

    final response = await http.post(
      Uri.parse('${SupabaseConfig.railwayBaseUrl}/voice-checkout/'),
      headers: {'Content-Type': 'application/json', 'X-Api-Key': SupabaseConfig.apiSecret},
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

    if (response.statusCode != 200) {
      throw Exception('Payment failed: ${response.statusCode}');
    }
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

    final response = await http.post(
      Uri.parse('${SupabaseConfig.railwayBaseUrl}/voice-checkout/'),
      headers: {'Content-Type': 'application/json', 'X-Api-Key': SupabaseConfig.apiSecret},
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

    if (response.statusCode != 200) {
      throw Exception('Deposit failed: ${response.statusCode}');
    }
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
    final res = await _client
        .from('stock_history')
        .select('*')
        .eq('stock_id', stockId)
        .eq('event_type', 'restock')
        .order('created_at', ascending: false)
        .limit(1);

    if ((res as List).isEmpty) return null;
    return StockHistoryEntry.fromMap(res.first);
  }

  // Units of a stock item sold this calendar month — scanned from bill_details
  // Returns true if a customer with [name] (case-insensitive) already exists
  // for this user, ignoring the customer with [excludeId] (for rename check #41).
  static Future<bool> checkCustomerNameExists(String name, {String? excludeId}) async {
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
  static Future<bool> checkItemNameExists(String name, {required String excludeStockId}) async {
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
    final monthEnd = DateTime(now.year, now.month + 1, 1).toUtc().toIso8601String();

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
        final matchById   = item['stock_id']?.toString() == stockId;
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
