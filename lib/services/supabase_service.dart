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

    final names = (res as List)
        .map((e) => e['customer_name']?.toString().trim() ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
    return names;
  }

  // ── Checkout ───────────────────────────────────────────────────────────────

  static Future<void> checkout({
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    required double discountAmount,
    String? customerName,
    required bool isCredit,
  }) async {
    final userId = _userId;
    if (userId == null) throw Exception('Not authenticated');

    if (customerName != null && customerName.trim().isNotEmpty) {
      await ensureCustomerExists(customerName);
    }

    final response = await http.post(
      Uri.parse('${SupabaseConfig.railwayBaseUrl}/voice-checkout/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'total_bill_amount': totalAmount,
        'discount_amount': discountAmount,
        'customer_name': customerName,
        'is_credit': isCredit,
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
        .gte('created_at', from.toIso8601String())
        .lte('created_at', to.toIso8601String());

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
        .select('total_amount, is_credit')
        .eq('user_id', userId)
        .not('customer_name', 'is', null);

    double total = 0;
    for (final bill in (res as List)) {
      final amount = (bill['total_amount'] as num?)?.toDouble() ?? 0;
      total += bill['is_credit'] == true ? amount : -amount;
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
        .select('customer_name, total_amount, is_credit, created_at')
        .eq('user_id', userId)
        .not('customer_name', 'is', null);

    // Aggregate bill amounts + last purchase date per customer name
    final Map<String, Map<String, dynamic>> agg = {};
    for (final bill in (billRes as List)) {
      final name = bill['customer_name'] as String;
      agg.putIfAbsent(name, () => {'credit': 0.0, 'paid': 0.0, 'lastDate': null});
      final amt = (bill['total_amount'] as num?)?.toDouble() ?? 0;
      if (bill['is_credit'] == true) {
        agg[name]!['credit'] = (agg[name]!['credit'] as double) + amt;
      } else {
        agg[name]!['paid'] = (agg[name]!['paid'] as double) + amt;
      }
      final date = DateTime.tryParse(bill['created_at'] as String? ?? '');
      final existing = agg[name]!['lastDate'] as DateTime?;
      if (date != null && (existing == null || date.isAfter(existing))) {
        agg[name]!['lastDate'] = date;
      }
    }

    final customers = (custRes as List).map((c) {
      final customer = Customer.fromMap(c);
      final data = agg[customer.name];
      if (data != null) {
        final credit = data['credit'] as double;
        final paid = data['paid'] as double;
        customer.outstanding =
            (customer.openingBalance + credit - paid).clamp(0, double.infinity);
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
        .select('*')
        .eq('user_id', userId)
        .eq('customer_name', customerName)
        .order('created_at', ascending: false);

    return (res as List).map((bill) => {
      'type': bill['is_credit'] == true ? 'credit' : 'payment',
      'amount': (bill['total_amount'] as num?)?.toDouble() ?? 0,
      'created_at': bill['created_at']?.toString(),
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
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'total_bill_amount': amount,
        'discount_amount': 0,
        'customer_name': customerName,
        'is_credit': false,
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
  static Future<double> fetchItemSalesThisMonth(String stockId) async {
    final userId = _userId;
    if (userId == null) return 0;

    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1).toIso8601String();

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
