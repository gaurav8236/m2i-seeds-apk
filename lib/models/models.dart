import 'dart:convert';

class StockItem {
  final String id;
  final double currentStock;
  final double sellingPrice;
  final double lowStockLimit;
  final List<String> aliases;
  final String itemName;
  final String category;
  final String unit;

  StockItem({
    required this.id,
    required this.currentStock,
    required this.sellingPrice,
    required this.lowStockLimit,
    required this.aliases,
    required this.itemName,
    required this.category,
    required this.unit,
  });

  factory StockItem.fromMap(Map<String, dynamic> map) {
    final master = map['master_inventory'] as Map<String, dynamic>? ?? {};
    return StockItem(
      id: map['id']?.toString() ?? '',
      currentStock: (map['current_stock'] as num?)?.toDouble() ?? 0,
      sellingPrice: (map['selling_price'] as num?)?.toDouble() ?? 0,
      lowStockLimit: (map['low_stock_limit'] as num?)?.toDouble() ?? 10,
      aliases: List<String>.from(map['aliases'] ?? []),
      itemName: master['item_name']?.toString() ?? '',
      category: master['category']?.toString() ?? '',
      unit: master['unit']?.toString() ?? '',
    );
  }

  bool get isLow => currentStock <= lowStockLimit;
}

class BillItem {
  String itemName;
  double quantity;
  double pricePerUnit;
  double itemTotal;
  double stockRemaining;
  String? stockId;
  double currentStock;
  String unit;
  bool hasError;
  String errorMessage;

  BillItem({
    required this.itemName,
    required this.quantity,
    required this.pricePerUnit,
    required this.itemTotal,
    required this.stockRemaining,
    this.stockId,
    required this.currentStock,
    required this.unit,
    this.hasError = false,
    this.errorMessage = '',
  });

  factory BillItem.fromMap(Map<String, dynamic> map) {
    return BillItem(
      itemName: map['item_name']?.toString() ?? '',
      quantity: (map['quantity_billed'] as num?)?.toDouble() ?? 1,
      pricePerUnit: (map['price_per_unit'] as num?)?.toDouble() ?? 0,
      itemTotal: (map['item_total'] as num?)?.toDouble() ?? 0,
      stockRemaining: (map['stock_remaining'] as num?)?.toDouble() ?? 0,
      stockId: map['stock_id']?.toString(),
      currentStock: (map['current_stock'] as num?)?.toDouble() ?? 0,
      unit: map['unit']?.toString() ?? '',
      hasError: map['error'] != null && map['error'] != false,
      errorMessage: map['error'] is String ? map['error'] : '',
    );
  }

  Map<String, dynamic> toMap() => {
    'stock_id': stockId,
    'new_stock': stockRemaining >= 0 ? stockRemaining : 0,
    'item_name': itemName,
    'quantity_billed': quantity,
    'price_per_unit': pricePerUnit,
    'item_total': itemTotal,
    'unit': unit,
    'error': hasError,
  };
}

class Bill {
  final String id;
  final DateTime createdAt;
  final String? customerName;
  final double totalAmount;
  final double? discountAmount;
  final bool isCredit;
  // 'sale' | 'credit' | 'payment' — falls back to is_credit for old rows.
  final String transactionType;
  final List<Map<String, dynamic>> billDetails;

  Bill({
    required this.id,
    required this.createdAt,
    this.customerName,
    required this.totalAmount,
    this.discountAmount,
    required this.isCredit,
    required this.transactionType,
    required this.billDetails,
  });

  factory Bill.fromMap(Map<String, dynamic> map) {
    final isCredit = map['is_credit'] == true;
    final txType = map['transaction_type']?.toString();
    return Bill(
      id: map['id']?.toString() ?? '',
      // .toLocal() so all display sites show IST not UTC (#7).
      createdAt: DateTime.tryParse(map['created_at'] ?? '')?.toLocal() ?? DateTime.now(),
      customerName: map['customer_name']?.toString(),
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
      discountAmount: (map['discount_amount'] as num?)?.toDouble(),
      isCredit: isCredit,
      // Back-compat: older rows may not have transaction_type set.
      transactionType: (txType != null && txType.isNotEmpty)
          ? txType
          : (isCredit ? 'credit' : 'sale'),
      billDetails: () {
        final raw = map['bill_details'];
        if (raw is String) {
          return List<Map<String, dynamic>>.from(jsonDecode(raw) as List);
        }
        return List<Map<String, dynamic>>.from(raw ?? []);
      }(),
    );
  }
}

class MasterItem {
  final String id;
  final String itemName;
  final String category;
  final String unit;

  String get name => itemName;

  MasterItem({
    required this.id,
    required this.itemName,
    required this.category,
    required this.unit,
  });

  factory MasterItem.fromMap(Map<String, dynamic> map) {
    return MasterItem(
      id: map['id']?.toString() ?? '',
      itemName: map['item_name']?.toString() ?? '',
      category: map['category']?.toString() ?? '',
      unit: map['unit']?.toString() ?? '',
    );
  }
}

class Customer {
  final String id;
  final String name;
  final String? phone;
  final double openingBalance;
  final DateTime createdAt;
  // Computed from past_bills after fetch:
  double outstanding;
  DateTime? lastPurchaseAt;

  Customer({
    required this.id,
    required this.name,
    this.phone,
    required this.openingBalance,
    required this.createdAt,
    this.outstanding = 0,
    this.lastPurchaseAt,
  });

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      phone: map['phone']?.toString(),
      openingBalance: (map['opening_balance'] as num?)?.toDouble() ?? 0,
      // .toLocal() for consistent IST display (#7).
      createdAt: DateTime.tryParse(map['created_at'] ?? '')?.toLocal() ?? DateTime.now(),
    );
  }
}

class StockHistoryEntry {
  final String id;
  final String stockId;
  final double quantityBefore;
  final double quantityAfter;
  final String eventType;
  final DateTime createdAt;

  double get quantityAdded => quantityAfter - quantityBefore;

  StockHistoryEntry({
    required this.id,
    required this.stockId,
    required this.quantityBefore,
    required this.quantityAfter,
    required this.eventType,
    required this.createdAt,
  });

  factory StockHistoryEntry.fromMap(Map<String, dynamic> map) {
    return StockHistoryEntry(
      id: map['id']?.toString() ?? '',
      stockId: map['stock_id']?.toString() ?? '',
      quantityBefore: (map['quantity_before'] as num?)?.toDouble() ?? 0,
      quantityAfter: (map['quantity_after'] as num?)?.toDouble() ?? 0,
      eventType: map['event_type']?.toString() ?? 'restock',
      // .toLocal() for consistent IST display (#7).
      createdAt: DateTime.tryParse(map['created_at'] ?? '')?.toLocal() ?? DateTime.now(),
    );
  }
}
