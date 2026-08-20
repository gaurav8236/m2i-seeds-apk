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

    final res = await _client
        .from('past_bills')
        .select('customer_name')
        .eq('user_id', userId)
        .not('customer_name', 'is', null);

    // Case-insensitive dedup: keep the first-seen casing for display but
    // ensure 'Ramesh' and 'ramesh' don't appear as two autocomplete entries.
    final seen  = <String>{};
    final names = <String>[];
    for (final e in (res as List)) {
      final raw = e['customer_name']?.toString().trim() ?? '';
      if (raw.isEmpty) continue;
      if (seen.add(raw.toLowerCase())) names.add(raw);
    }
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
        .select('total_amount, is_credit')
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

    double credit = 0, paid = 0;
    for (final bill in (res as List)) {
      final amount = (bill['total_amount'] as num?)?.toDouble() ?? 0;
      if (bill['is_credit'] == true) {
        credit += amount;
      } else {
        paid += amount;
      }
    }
    return {'credit': credit, 'paid': paid};
  }

  // Total unpaid उधार across ALL customers — not period-filtered
  static Future<double> fetchTotalOutstanding() async {
    final userId = _userId;
    if (userId == null) return 0;

    final res = await _client
        .from('past_bills')
        .select('total_amount, is_credit, nagad_amount, transaction_type')
        .eq('user_id', userId)
        .not('customer_name', 'is', null);

    double total = 0;
    for (final bill in (res as List)) {
      final amount = (bill['total_amount'] as num?)?.toDouble() ?? 0;
      final nagad  = (bill['nagad_amount'] as num?)?.toDouble() ?? 0;
      final txType = (bill['transaction_type'] as String?)?.trim() ?? '';
      if (bill['is_credit'] == true) {
        total += (amount - nagad).clamp(0, double.infinity);
      } else if (txType == 'payment' || txType == 'deposit') {
        // Only explicit payment receipts and deposits reduce outstanding.
        // Cash sales (txType='sale' or pre-Sprint-3 NULL) have no outstanding impact.
        total -= amount;
      }
    }
    return total.clamp(0, double.infinity);
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
        .select('customer_name, total_amount, is_credit, nagad_amount, transaction_type, created_at')
        .eq('user_id', userId)
        .not('customer_name', 'is', null);

    // Aggregate bill amounts + last purchase date per customer name.
    // Key is lowercased so 'Ramesh' and 'ramesh' merge correctly (case-insensitive dedup).
    final Map<String, Map<String, dynamic>> agg = {};
    for (final bill in (billRes as List)) {
      final name    = (bill['customer_name'] as String).trim();
      final nameKey = name.toLowerCase();
      agg.putIfAbsent(nameKey, () => {'credit': 0.0, 'paid': 0.0, 'lastDate': null});
      final amt    = (bill['total_amount'] as num?)?.toDouble() ?? 0;
      final nagad  = (bill['nagad_amount'] as num?)?.toDouble() ?? 0;
      final txType = (bill['transaction_type'] as String?)?.trim() ?? '';
      if (bill['is_credit'] == true) {
        // For split bills: only (total - nagad) goes to outstanding
        agg[nameKey]!['credit'] = (agg[nameKey]!['credit'] as double) + (amt - nagad).clamp(0, double.infinity);
      } else if (txType == 'payment' || txType == 'deposit') {
        // Explicit payment / advance deposit — reduces outstanding.
        // Cash sales (txType == 'sale' or '') have no impact on the unpaid balance.
        agg[nameKey]!['paid'] = (agg[nameKey]!['paid'] as double) + amt;
      }
      // is_credit=false + txType='sale' (or pre-Sprint-3 NULL): cash sale, no outstanding change.
      final date = DateTime.tryParse(bill['created_at'] as String? ?? '');
      final existing = agg[nameKey]!['lastDate'] as DateTime?;
      if (date != null && (existing == null || date.isAfter(existing))) {
        agg[nameKey]!['lastDate'] = date;
      }
    }

    final customers = (custRes as List).map((c) {
      final customer = Customer.fromMap(c);
      final data = agg[customer.name.toLowerCase()];
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

  // Called before checkout to ensure customer exists in the customers table
  // C-05: update phone / opening_balance. Name edits are blocked at the UI
  // layer if the customer has any past bills.
  static Future<void> updateCustomer({
    required String id,
    String? phone,       // pass '' to clear, null to leave unchanged
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
    await _client
        .from('customers')
        .delete()
        .eq('id', id)
        .eq('user_id', userId);
  }

  static Future<void> ensureCustomerExists(String customerName) async {
    final userId = _userId;
    if (userId == null) return;
    await _client.from('customers').upsert(
      {'user_id': userId, 'name': customerName.trim()},
      onConflict: 'user_id,name',
      ignoreDuplicates: true,
    );
  }

  // ── Customer Ledger ────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchCustomerLedger(String customerName) async {
    final userId = _userId;
    if (userId == null) return [];

    final res = await _client
        .from('past_bills')
        .select('total_amount, is_credit, nagad_amount, transaction_type, created_at')
        .eq('user_id', userId)
        .eq('customer_name', customerName)
        .order('created_at', ascending: true); // ascending: running-balance computation needs oldest-first

    return (res as List).map((bill) {
      final isCredit = bill['is_credit'] == true;
      final nagad = (bill['nagad_amount'] as num?)?.toDouble() ?? 0;
      final txType = bill['transaction_type'] as String? ?? '';
      // Determine display type
      final String type;
      if (!isCredit && txType == 'payment') {
        type = 'payment';
      } else if (!isCredit && txType == 'deposit') {
        type = 'deposit';
      } else if (isCredit && nagad > 0) {
        type = 'split';
      } else if (isCredit) {
        type = 'credit';
      } else {
        type = 'cash';
      }
      return {
        'type': type,
        'amount': (bill['total_amount'] as num?)?.toDouble() ?? 0,
        'nagad_amount': nagad,
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
  static Future<double> fetchItemSalesThisMonth(String stockId) async {
    final userId = _userId;
    if (userId == null) return 0;

    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1).toUtc().toIso8601String();

    final res = await _client
        .from('past_bills')
        .select('bill_details')
        .eq('user_id', userId)
        .gte('created_at', firstDay);

    double totalQty = 0;
    for (final bill in (res as List)) {
      final details =
          List<Map<String, dynamic>>.from(bill['bill_details'] ?? []);
      for (final item in details) {
        if (item['stock_id']?.toString() == stockId) {
          totalQty += (item['quantity_billed'] as num?)?.toDouble() ?? 0;
        }
      }
    }
    return totalQty;
  }
}
