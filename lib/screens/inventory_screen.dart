import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../theme.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<StockItem> _stock = [];
  List<MasterItem> _masterInventory = [];
  bool _loading = true;
  String _searchQuery = '';
  String _filterCategory = 'All';
  bool _showLowOnly = false;
  bool _saving = false;

  // Inline edits: stockId → {price, stock, lowLimit}
  final Map<String, Map<String, double>> _edits = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stock = await SupabaseService.fetchStock();
      final master = await SupabaseService.fetchMasterInventory();
      setState(() {
        _stock = stock;
        _masterInventory = master;
      });
    } catch (e) {
      _showSnack('लोड नहीं हो सका: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  List<String> get _categories {
    final cats = {'All', ..._stock.map((s) => s.category).where((c) => c.isNotEmpty)};
    return cats.toList();
  }

  List<StockItem> get _filtered {
    return _stock.where((s) {
      final q = _searchQuery.toLowerCase();
      final nameMatch = s.itemName.toLowerCase().contains(q);
      final catMatch = _filterCategory == 'All' || s.category == _filterCategory;
      final lowMatch = !_showLowOnly || s.isLow;
      return nameMatch && catMatch && lowMatch;
    }).toList();
  }

  double _editedPrice(StockItem s) => _edits[s.id]?['price'] ?? s.sellingPrice;
  double _editedStock(StockItem s) => _edits[s.id]?['stock'] ?? s.currentStock;
  double _editedLimit(StockItem s) => _edits[s.id]?['limit'] ?? s.lowStockLimit;

  void _setEdit(String id, String field, double value) {
    _edits.putIfAbsent(id, () => {});
    _edits[id]![field] = value;
    setState(() {});
  }

  bool get _hasPendingEdits => _edits.isNotEmpty;

  Future<void> _saveAll() async {
    if (_edits.isEmpty) return;
    setState(() => _saving = true);
    try {
      final updates = _edits.entries.map((e) {
        final stock = _stock.firstWhere((s) => s.id == e.key);
        return {
          'id': e.key,
          'selling_price': e.value['price'] ?? stock.sellingPrice,
          'current_stock': e.value['stock'] ?? stock.currentStock,
          'low_stock_limit': e.value['limit'] ?? stock.lowStockLimit,
        };
      }).toList();
      await SupabaseService.upsertInventoryItems(updates);
      _edits.clear();
      await _load();
      _showSnack('सेव हो गया!');
    } catch (e) {
      _showSnack('सेव नहीं हो सका: $e');
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _addItemFromMaster() async {
    final filtered = _masterInventory
        .where((m) => !_stock.any((s) => s.itemName == m.name))
        .toList();

    if (filtered.isEmpty) {
      _showSnack('सभी आइटम पहले से जुड़े हैं');
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AddItemSheet(masterItems: filtered, onAdd: (item) async {
        await SupabaseService.upsertInventoryItems([item]);
        await _load();
        Navigator.pop(ctx);
      }),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          // Header
          Container(
            decoration: BoxDecoration(
              gradient: primaryGradient,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.inventory_2, color: Colors.white, size: 17),
                        ),
                        const SizedBox(width: 8),
                        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('स्टॉक प्रबंधन', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                          Text('Inventory', style: TextStyle(color: Colors.white70, fontSize: 10)),
                        ]),
                      ]),
                      Row(children: [
                        if (_hasPendingEdits)
                          TextButton.icon(
                            onPressed: _saving ? null : _saveAll,
                            icon: _saving
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.save, color: Colors.white, size: 15),
                            label: const Text('सेव', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                            style: TextButton.styleFrom(
                              backgroundColor: AppColors.success,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            ),
                          ),
                        const SizedBox(width: 6),
                        TextButton.icon(
                          onPressed: _addItemFromMaster,
                          icon: const Icon(Icons.add, color: Colors.white, size: 15),
                          label: const Text('जोड़ें', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(color: Colors.white.withOpacity(0.3)),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          ),
                        ),
                      ]),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Stats bar
                  Row(
                    children: [
                      _statPill('कुल', _stock.length.toString(), false),
                      const SizedBox(width: 8),
                      _statPill('कम स्टॉक', _stock.where((s) => s.isLow).length.toString(), true),
                    ],
                  ),
                ]),
              ),
            ),
          ),

          // Search + filters
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Column(children: [
              TextField(
                decoration: const InputDecoration(
                  hintText: 'आइटम खोजें...',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _categories.map((cat) => GestureDetector(
                          onTap: () => setState(() => _filterCategory = cat),
                          child: Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: _filterCategory == cat ? AppColors.primary : AppColors.surface2,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _filterCategory == cat ? AppColors.primary : AppColors.border,
                              ),
                            ),
                            child: Text(cat,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _filterCategory == cat ? Colors.white : AppColors.textSecondary,
                                )),
                          ),
                        )).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _showLowOnly = !_showLowOnly),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _showLowOnly ? AppColors.warningLight : AppColors.surface2,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _showLowOnly ? AppColors.warning : AppColors.border,
                        ),
                      ),
                      child: Row(children: [
                        Icon(Icons.warning_amber_rounded, size: 13,
                            color: _showLowOnly ? AppColors.warning : AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text('कम',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                color: _showLowOnly ? AppColors.warning : AppColors.textMuted)),
                      ]),
                    ),
                  ),
                ],
              ),
            ]),
          ),

          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _stockCard(_filtered[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statPill(String label, String value, bool warn) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(warn ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Row(children: [
        if (warn) const Icon(Icons.warning_amber_rounded, size: 13, color: Colors.white),
        if (warn) const SizedBox(width: 4),
        Text('$value $label', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _stockCard(StockItem stock) {
    final isEdited = _edits.containsKey(stock.id);
    final price = _editedPrice(stock);
    final qty = _editedStock(stock);
    final limit = _editedLimit(stock);
    final isLow = qty <= limit;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLow ? const Color(0xFFFDE68A) : (isEdited ? AppColors.primaryLight : AppColors.border),
          width: isLow || isEdited ? 1.5 : 1,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: name + badges
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stock.itemName,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      if (stock.category.isNotEmpty)
                        Text(stock.category,
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                Row(children: [
                  if (isLow)
                    _badge('कम स्टॉक', AppColors.warning, AppColors.warningLight),
                  if (stock.unit.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _badge(stock.unit, AppColors.textSecondary, AppColors.surface2),
                  ],
                ]),
              ],
            ),
            const SizedBox(height: 12),

            // Editable fields row
            Row(
              children: [
                Expanded(child: _editField(
                  label: 'दर (₹)',
                  value: price,
                  onChanged: (v) => _setEdit(stock.id, 'price', v),
                  prefix: '₹',
                )),
                const SizedBox(width: 8),
                Expanded(child: _editField(
                  label: 'स्टॉक',
                  value: qty,
                  onChanged: (v) => _setEdit(stock.id, 'stock', v),
                )),
                const SizedBox(width: 8),
                Expanded(child: _editField(
                  label: 'न्यूनतम',
                  value: limit,
                  onChanged: (v) => _setEdit(stock.id, 'limit', v),
                )),
              ],
            ),

            if (isEdited) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () { setState(() => _edits.remove(stock.id)); },
                    child: const Text('रद्द करें', style: TextStyle(fontSize: 11, color: AppColors.danger, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _editField({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    String? prefix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextFormField(
          initialValue: value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(2),
          keyboardType: TextInputType.number,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
          decoration: InputDecoration(
            prefixText: prefix,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          ),
          onChanged: (v) {
            final parsed = double.tryParse(v);
            if (parsed != null) onChanged(parsed);
          },
        ),
      ],
    );
  }

  Widget _badge(String text, Color textColor, Color bgColor) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: textColor.withOpacity(0.3)),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: textColor)),
      );
}

// ── Add-item bottom sheet ────────────────────────────────────────────────────

class _AddItemSheet extends StatefulWidget {
  final List<MasterItem> masterItems;
  final Future<void> Function(Map<String, dynamic>) onAdd;

  const _AddItemSheet({required this.masterItems, required this.onAdd});

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  MasterItem? _selected;
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '0');
  final _limitCtrl = TextEditingController(text: '5');
  bool _saving = false;
  String _search = '';

  @override
  void dispose() {
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  List<MasterItem> get _filtered => widget.masterItems
      .where((m) => m.name.toLowerCase().contains(_search.toLowerCase()))
      .toList();

  Future<void> _submit() async {
    if (_selected == null) return;
    setState(() => _saving = true);
    await widget.onAdd({
      'master_inventory_id': _selected!.id,
      'selling_price': double.tryParse(_priceCtrl.text) ?? 0,
      'current_stock': double.tryParse(_stockCtrl.text) ?? 0,
      'low_stock_limit': double.tryParse(_limitCtrl.text) ?? 5,
    });
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        maxChildSize: 0.85,
        builder: (_, ctrl) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Text('आइटम जोड़ें', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ]),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'खोजें...',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                controller: ctrl,
                children: [
                  if (_selected != null)
                    _selectedForm()
                  else
                    ..._filtered.map((m) => ListTile(
                          title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${m.category} · ${m.unit}',
                              style: const TextStyle(fontSize: 11)),
                          trailing: const Icon(Icons.chevron_right, size: 16),
                          onTap: () => setState(() {
                            _selected = m;
                            _priceCtrl.text = '0';
                          }),
                        )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectedForm() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_selected!.name,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            GestureDetector(
              onTap: () => setState(() => _selected = null),
              child: const Text('बदलें', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _input('बिक्री दर (₹)', _priceCtrl, prefix: '₹'),
        const SizedBox(height: 12),
        _input('वर्तमान स्टॉक', _stockCtrl),
        const SizedBox(height: 12),
        _input('न्यूनतम स्टॉक सीमा', _limitCtrl),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : const Text('जोड़ें', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ]),
    );
  }

  Widget _input(String label, TextEditingController ctrl, {String? prefix}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
      const SizedBox(height: 4),
      TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(prefixText: prefix, isDense: true),
      ),
    ]);
  }
}
