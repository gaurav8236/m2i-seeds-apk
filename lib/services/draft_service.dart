import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class DraftBill {
  final String id;
  final List<BillItem> items;
  final double discount;
  final String customerName;
  final DateTime savedAt;

  DraftBill({
    required this.id,
    required this.items,
    required this.discount,
    required this.customerName,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'items': items.map((i) => i.toMap()).toList(),
    'discount': discount,
    'customerName': customerName,
    'savedAt': savedAt.toIso8601String(),
  };

  factory DraftBill.fromJson(Map<String, dynamic> json) => DraftBill(
    id: json['id'] as String,
    items: (json['items'] as List)
        .map((i) => BillItem.fromMap(i as Map<String, dynamic>))
        .toList(),
    discount: (json['discount'] as num?)?.toDouble() ?? 0,
    customerName: json['customerName'] as String? ?? '',
    savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class DraftService {
  static const _key = 'smartdukan_drafts';

  static Future<List<DraftBill>> loadDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => DraftBill.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveDraft(DraftBill draft) async {
    final drafts = await loadDrafts();
    // Replace if same id, otherwise prepend
    final idx = drafts.indexWhere((d) => d.id == draft.id);
    if (idx >= 0) {
      drafts[idx] = draft;
    } else {
      drafts.insert(0, draft);
    }
    await _persist(drafts);
  }

  static Future<void> deleteDraft(String id) async {
    final drafts = await loadDrafts();
    drafts.removeWhere((d) => d.id == id);
    await _persist(drafts);
  }

  static Future<void> _persist(List<DraftBill> drafts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(drafts.map((d) => d.toJson()).toList()));
  }
}
