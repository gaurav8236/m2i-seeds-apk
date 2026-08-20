import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../theme.dart';

class StockItemDetailScreen extends StatefulWidget {
  final StockItem item;
  const StockItemDetailScreen({super.key, required this.item});

  @override
  State<StockItemDetailScreen> createState() => _StockItemDetailScreenState();
}

class _StockItemDetailScreenState extends State<StockItemDetailScreen> {
  bool _saving = false;
  bool _insightsLoading = true;
  double _soldThisMonth = 0;
  StockHistoryEntry? _lastRestock;

  late final _nameCtrl = TextEditingController(text: widget.item.itemName);
  late final _priceCtrl =
      TextEditingController(text: widget.item.sellingPrice.toInt().toString());
  late final _stockCtrl = TextEditingController(
      text: widget.item.currentStock.toInt().toString());
  late final _aliasCtrl = TextEditingController();
  late double _lowStockLimit = widget.item.lowStockLimit;
  late List<String> _aliases = List.from(widget.item.aliases);
  bool _isDirty = false;

  // I-01: category and unit are driven by dropdown selection.
  // 'अन्य' sentinel triggers a custom text field below.
  static const List<String> _categories = [
    'अनाज', 'दाल', 'तेल', 'मसाले', 'नमकीन / स्नैक्स',
    'बिस्किट / मिठाई', 'साबुन / डिटर्जेंट',
    'पेय / कोल्ड ड्रिंक', 'डेयरी', 'अन्य',
  ];
  static const List<String> _units = [
    'किलो', 'ग्राम', 'लीटर', 'मिली',
    'नग', 'पैकेट', 'दर्जन', 'थैला', 'बोरी', 'अन्य',
  ];
  static const String _customSentinel = 'अन्य';

  late String _selectedCategory = _canonicalCategory(widget.item.category);
  late String _selectedUnit     = _canonicalUnit(widget.item.unit);
  late final _customCategoryCtrl =
      TextEditingController(text: _isCustomCategory ? widget.item.category : '');
  late final _customUnitCtrl =
      TextEditingController(text: _isCustomUnit ? widget.item.unit : '');

  bool get _isCustomCategory => !_categories.contains(widget.item.category) ||
      _selectedCategory == _customSentinel;
  bool get _isCustomUnit => !_units.contains(widget.item.unit) ||
      _selectedUnit == _customSentinel;

  // Map item value to closest preset or 'अन्य'
  String _canonicalCategory(String v) =>
      _categories.contains(v) ? v : _customSentinel;
  String _canonicalUnit(String v) =>
      _units.contains(v) ? v : _customSentinel;

  // Resolved value to save
  String get _effectiveCategory =>
      _selectedCategory == _customSentinel
          ? _customCategoryCtrl.text.trim()
          : _selectedCategory;
  String get _effectiveUnit =>
      _selectedUnit == _customSentinel
          ? _customUnitCtrl.text.trim()
          : _selectedUnit;

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _aliasCtrl.dispose();
    _customCategoryCtrl.dispose();
    _customUnitCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInsights() async {
    if (widget.item.id.isEmpty) return;
    final results = await Future.wait([
      SupabaseService.fetchItemSalesThisMonth(widget.item.id),
      SupabaseService.fetchLastRestock(widget.item.id),
    ]);
    setState(() {
      _soldThisMonth = results[0] as double;
      _lastRestock = results[1] as StockHistoryEntry?;
      _insightsLoading = false;
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text);
    final newStock = double.tryParse(_stockCtrl.text);
    if (name.isEmpty || price == null || newStock == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('नाम, कीमत और स्टॉक भरें')));
      return;
    }

    // I-01: validate custom category/unit when 'अन्य' is selected
    if (_selectedCategory == _customSentinel &&
        _customCategoryCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('अन्य श्रेणी का नाम भरें')));
      return;
    }
    if (_selectedUnit == _customSentinel &&
        _customUnitCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('अन्य इकाई का नाम भरें')));
      return;
    }

    setState(() => _saving = true);
    try {
      // Log restock if stock increased
      if (newStock > widget.item.currentStock && widget.item.id.isNotEmpty) {
        await SupabaseService.logRestock(
          stockId: widget.item.id,
          quantityBefore: widget.item.currentStock,
          quantityAfter: newStock,
        );
      }

      await SupabaseService.upsertInventoryItems([{
        'item_name': name,
        'category': _effectiveCategory,
        'unit': _effectiveUnit,
        'selling_price': price,
        'current_stock': newStock,
        'low_stock_limit': _lowStockLimit,
        'aliases': _aliases,
        'cost_price': 0.0,
        'image_url': null,
      }]);

      if (mounted) {
        setState(() => _isDirty = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('सहेज दिया गया')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('त्रुटि: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleBack() async {
    if (!_isDirty) { Navigator.pop(context); return; }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('बदलाव छोड़ें?'),
        content: const Text('सहेजे बिना जाने पर बदलाव खो जाएंगे।'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('रहने दें'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('छोड़ें',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if ((leave ?? false) && mounted) Navigator.pop(context);
  }

  void _addAlias() {
    final a = _aliasCtrl.text.trim();
    if (a.isNotEmpty && !_aliases.contains(a)) {
      setState(() => _aliases.add(a));
      _aliasCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(children: [
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
              child: Row(children: [
                IconButton(
                  onPressed: _handleBack,
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.item.itemName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16),
                        overflow: TextOverflow.ellipsis),
                    const Text('सामान विवरण',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ]),
                ),
              ]),
            ),
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              // ── Edit fields ──────────────────────────────────────────────
              _section(children: [
                _lbl('सामान का नाम'),
                const SizedBox(height: 6),
                TextField(controller: _nameCtrl,
                    onChanged: (_) => setState(() => _isDirty = true),
                    decoration: const InputDecoration(isDense: true)),
                const SizedBox(height: 14),
                // I-01: category and unit dropdowns
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _lbl('श्रेणी'),
                    const SizedBox(height: 6),
                    _dropdownField(
                      value: _selectedCategory,
                      items: _categories,
                      onChanged: (v) => setState(() {
                        _selectedCategory = v!;
                        _isDirty = true;
                      }),
                    ),
                    if (_selectedCategory == _customSentinel) ...[
                      const SizedBox(height: 6),
                      TextField(
                        controller: _customCategoryCtrl,
                        onChanged: (_) => setState(() => _isDirty = true),
                        decoration: const InputDecoration(
                            hintText: 'श्रेणी लिखें', isDense: true),
                      ),
                    ],
                  ])),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _lbl('इकाई'),
                    const SizedBox(height: 6),
                    _dropdownField(
                      value: _selectedUnit,
                      items: _units,
                      onChanged: (v) => setState(() {
                        _selectedUnit = v!;
                        _isDirty = true;
                      }),
                    ),
                    if (_selectedUnit == _customSentinel) ...[
                      const SizedBox(height: 6),
                      TextField(
                        controller: _customUnitCtrl,
                        onChanged: (_) => setState(() => _isDirty = true),
                        decoration: const InputDecoration(
                            hintText: 'इकाई लिखें', isDense: true),
                      ),
                    ],
                  ])),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _lbl('बिक्री कीमत (₹)'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() => _isDirty = true),
                      decoration: const InputDecoration(
                          prefixText: '₹ ', isDense: true),
                    ),
                  ])),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _lbl('वर्तमान स्टॉक'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _stockCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() => _isDirty = true),
                      decoration: const InputDecoration(isDense: true),
                    ),
                  ])),
                ]),
                const SizedBox(height: 14),
                // Aliases
                _lbl('Voice Aliases (बोलने के नाम)'),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _aliasCtrl,
                      decoration: const InputDecoration(
                          hintText: 'उदा. चावल, बासमती', isDense: true),
                      onSubmitted: (_) => _addAlias(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _addAlias,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.add, color: AppColors.primary, size: 20),
                    ),
                  ),
                ]),
                if (_aliases.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6, runSpacing: 6,
                    children: _aliases.map((a) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.mic, size: 11, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(a, style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => setState(() => _aliases.remove(a)),
                          child: const Icon(Icons.close, size: 12,
                              color: AppColors.textMuted),
                        ),
                      ]),
                    )).toList(),
                  ),
                ],
                const SizedBox(height: 14),
                // Low stock slider
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _lbl('कम स्टॉक चेतावनी'),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_lowStockLimit.toInt()} ${_effectiveUnit.isNotEmpty ? _effectiveUnit : 'units'}',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12),
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: AppColors.border,
                    thumbColor: AppColors.primary,
                  ),
                  child: Slider(
                    value: _lowStockLimit,
                    min: 0, max: 100,
                    onChanged: (v) =>
                        setState(() { _lowStockLimit = v.roundToDouble(); _isDirty = true; }),
                  ),
                ),
              ]),

              const SizedBox(height: 16),

              // ── Insights ─────────────────────────────────────────────────
              _section(children: [
                const Text('इस महीने की जानकारी',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: AppColors.textMuted, letterSpacing: 0.6)),
                const SizedBox(height: 14),
                if (_insightsLoading)
                  const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ))
                else
                  Row(children: [
                    Expanded(
                      child: _insightCell(
                        label: 'इस महीने बिका',
                        value: '${_soldThisMonth % 1 == 0 ? _soldThisMonth.toInt() : _soldThisMonth.toStringAsFixed(1)} ${widget.item.unit}',
                        icon: Icons.trending_up,
                        color: AppColors.success,
                        bgColor: AppColors.successLight,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _insightCell(
                        label: 'आखिरी रीस्टॉक',
                        value: _lastRestock != null
                            ? '+${_lastRestock!.quantityAdded.toInt()} ${widget.item.unit}\n${DateFormat('dd MMM').format(_lastRestock!.createdAt)}'
                            : 'कोई रिकॉर्ड नहीं',
                        icon: Icons.inventory_2_outlined,
                        color: AppColors.primary,
                        bgColor: AppColors.primaryLight,
                      ),
                    ),
                  ]),
              ]),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Text('सहेजें',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ),
      ]),
    ), // Scaffold
    ); // PopScope
  }

  Widget _insightCell({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: color)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }

  Widget _section({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  // I-01: shared styled dropdown
  Widget _dropdownField({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isDense: true,
      isExpanded: true,
      decoration: const InputDecoration(isDense: true),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _lbl(String t) => Text(t,
      style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary));
}
