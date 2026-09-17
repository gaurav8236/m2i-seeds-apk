import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import '../utils/errors.dart';
import '../utils/unit_categories.dart';
import '../utils/validators.dart';

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

  // Category and unit dropdowns — initialized in initState after normalization.
  // Declared separately (not late final with inline init) so we can assign
  // the normalized canonical value before the first build (#23 bilingual Sprint 8).
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _unitCtrl;
  String? _selCategory;
  String? _selUnit;

  late final _nameCtrl = TextEditingController(text: widget.item.itemName);
  late final _priceCtrl = TextEditingController(
      text: widget.item.sellingPrice % 1 == 0
          ? widget.item.sellingPrice.toInt().toString()
          : widget.item.sellingPrice.toStringAsFixed(1));
  late final _stockCtrl = TextEditingController(
      text: widget.item.currentStock % 1 == 0
          ? widget.item.currentStock.toInt().toString()
          : widget.item.currentStock.toStringAsFixed(1));
  late final _aliasCtrl = TextEditingController();
  late double _lowStockLimit = widget.item.lowStockLimit;
  late List<String> _aliases = List.from(widget.item.aliases);
  bool _isDirty = false;

  // I-01: category and unit are driven by dropdown selection.
  // 'अन्य' sentinel triggers a custom text field below.
  static const List<String> _categories = [
    'अनाज',
    'दाल',
    'तेल',
    'मसाले',
    'नमकीन / स्नैक्स',
    'बिस्किट / मिठाई',
    'साबुन / डिटर्जेंट',
    'पेय / कोल्ड ड्रिंक',
    'डेयरी',
    'अन्य',
  ];
  static const List<String> _units = [
    'किलो',
    'ग्राम',
    'लीटर',
    'मिली',
    'नग',
    'पैकेट',
    'दर्जन',
    'थैला',
    'बोरी',
    'अन्य',
  ];
  static const String _customSentinel = 'अन्य';

  late String _selectedCategory = _canonicalCategory(widget.item.category);
  late String _selectedUnit = _canonicalUnit(widget.item.unit);
  late final _customCategoryCtrl = TextEditingController(
      text: _isCustomCategory ? widget.item.category : '');
  late final _customUnitCtrl =
      TextEditingController(text: _isCustomUnit ? widget.item.unit : '');

  bool get _isCustomCategory =>
      !_categories.contains(widget.item.category) ||
      _selectedCategory == _customSentinel;
  bool get _isCustomUnit =>
      !_units.contains(widget.item.unit) || _selectedUnit == _customSentinel;

  // Map item value to closest preset or 'अन्य'
  String _canonicalCategory(String v) =>
      _categories.contains(v) ? v : _customSentinel;
  String _canonicalUnit(String v) => _units.contains(v) ? v : _customSentinel;

  // Resolved value to save
  String get _effectiveCategory => _selectedCategory == _customSentinel
      ? _customCategoryCtrl.text.trim()
      : _selectedCategory;
  String get _effectiveUnit => _selectedUnit == _customSentinel
      ? _customUnitCtrl.text.trim()
      : _selectedUnit;

  @override
  void initState() {
    super.initState();
    // Normalize the stored value (may be "kg", "KG", etc.) to canonical Hindi
    // before populating dropdowns and text controllers (#23 bilingual Sprint 8).
    final normCat =
        normalizeCategory(widget.item.category) ?? widget.item.category;
    final normUnit = normalizeUnit(widget.item.unit) ?? widget.item.unit;
    _categoryCtrl = TextEditingController(text: normCat);
    _unitCtrl = TextEditingController(text: normUnit);
    _selCategory = kCategories.any((c) => c.canonical == normCat)
        ? normCat
        : (normCat.isNotEmpty ? 'अन्य' : null);
    _selUnit = kUnits.any((u) => u.canonical == normUnit)
        ? normUnit
        : (normUnit.isNotEmpty ? 'अन्य' : null);
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
    try {
      final results = await Future.wait([
        SupabaseService.fetchItemSalesThisMonth(widget.item.id,
            itemName: widget.item.itemName),
        SupabaseService.fetchLastRestock(widget.item.id),
      ]);
      if (mounted)
        setState(() {
          _soldThisMonth = results[0] as double;
          _lastRestock = results[1] as StockHistoryEntry?;
          _insightsLoading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _insightsLoading = false);
    }
  }

  Future<void> _save() async {
    // Resolve effective unit/category from dropdown selection or free-text field.
    final rawUnit =
        _selUnit == 'अन्य' ? _unitCtrl.text.trim() : (_selUnit ?? '');
    final rawCategory = _selCategory == 'अन्य'
        ? _categoryCtrl.text.trim()
        : (_selCategory ?? '');
    final nameErr = Validators.itemName(_nameCtrl.text);
    final priceErr = Validators.sellingPrice(_priceCtrl.text);
    final stockErr = Validators.currentStock(_stockCtrl.text);
    final unitErr =
        Validators.unit(rawUnit); // rejects purely numeric values (#4)
    final firstErr = nameErr ?? priceErr ?? stockErr ?? unitErr;
    if (firstErr != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(firstErr)));
      return;
    }
    final name = _nameCtrl.text.trim();
    final price = double.parse(_priceCtrl.text.trim());
    final newStock = double.parse(_stockCtrl.text.trim());
    // Normalize to canonical Hindi before writing to DB (bilingual Sprint 8).
    final canonicalUnit = normalizeUnit(rawUnit) ?? rawUnit;
    final canonicalCategory = normalizeCategory(rawCategory) ?? rawCategory;

    // Validate custom category/unit text when 'अन्य' is selected — the
    // dropdown allows selecting 'अन्य' without ever touching the text field
    // below it, which would otherwise save an empty category/unit.
    if (_selCategory == 'अन्य' && _categoryCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('अन्य श्रेणी का नाम भरें')));
      return;
    }
    if (_selUnit == 'अन्य' && _unitCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('अन्य इकाई का नाम भरें')));
      return;
    }

    // Guard against double-tap: set _saving before any async work so a
    // second tap while the name-check is in flight is a no-op.
    setState(() => _saving = true);

    // Duplicate item-name check: warn before save if another item already has
    // this name (case-insensitive) for this user (#32).
    if (name.toLowerCase() != widget.item.itemName.trim().toLowerCase()) {
      try {
        final taken = await SupabaseService.checkItemNameExists(name,
            excludeStockId: widget.item.id);
        if (!mounted) return;
        if (taken) {
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('\'$name\' नाम का सामान पहले से है')));
          return;
        }
      } catch (_) {
        // Name-check failure is non-fatal — proceed with save.
      }
    }
    try {
      // Log restock if stock increased
      if (newStock > widget.item.currentStock && widget.item.id.isNotEmpty) {
        await SupabaseService.logRestock(
          stockId: widget.item.id,
          quantityBefore: widget.item.currentStock,
          quantityAfter: newStock,
        );
      }

      // Use ID-based direct update instead of the name-keyed upsert RPC.
      // The RPC creates a new item when the name changes (#22); this path
      // updates the existing row correctly, and also avoids the RPC error
      // seen after logRestock (#20).
      await SupabaseService.updateInventoryItem(
        stockId: widget.item.id,
        itemName: name,
        category: canonicalCategory,
        unit: canonicalUnit,
        sellingPrice: price,
        currentStock: newStock,
        lowStockLimit: _lowStockLimit,
        aliases: _aliases,
      );

      if (mounted) {
        setState(() => _isDirty = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('सहेज दिया गया')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(Errors.friendlyMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleBack() async {
    if (!_isDirty) {
      Navigator.pop(context);
      return;
    }
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
            child: const Text('छोड़ें', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if ((leave ?? false) && mounted) Navigator.pop(context);
  }

  void _addAlias() {
    final a = _aliasCtrl.text.trim();
    // Validate length (#24)
    final err = Validators.alias(a);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    // Case-insensitive duplicate check (#30)
    final aLower = a.toLowerCase();
    final alreadyExists = _aliases.any((e) => e.toLowerCase() == aLower);
    if (!alreadyExists) {
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
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.item.itemName,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16),
                              overflow: TextOverflow.ellipsis),
                          const Text('सामान विवरण',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                        ]),
                  ),
                ]),
              ),
            ),
          ),

          // SafeArea(top:false) so save button clears home indicator (#18)
          Expanded(
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  // ── Edit fields ──────────────────────────────────────────────
                  _section(children: [
                    _lbl('सामान का नाम'),
                    const SizedBox(height: 6),
                    TextField(
                        controller: _nameCtrl,
                        onChanged: (_) => setState(() => _isDirty = true),
                        decoration: const InputDecoration(isDense: true)),
                    const SizedBox(height: 14),
                    // Category + Unit — bilingual dropdowns (#23 Sprint 8)
                    Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            _lbl('श्रेणी'),
                            const SizedBox(height: 6),
                            _dropdownField(
                              value: _selCategory,
                              items: kCategories,
                              hint: 'चुनें',
                              onChanged: (v) => setState(() {
                                _selCategory = v;
                                if (v != null && v != 'अन्य')
                                  _categoryCtrl.text = v;
                                else if (v == 'अन्य') _categoryCtrl.text = '';
                                _isDirty = true;
                              }),
                            ),
                            if (_selCategory == 'अन्य') ...[
                              const SizedBox(height: 6),
                              TextField(
                                  controller: _categoryCtrl,
                                  onChanged: (_) =>
                                      setState(() => _isDirty = true),
                                  decoration: const InputDecoration(
                                      hintText: 'श्रेणी लिखें...',
                                      isDense: true)),
                            ],
                          ])),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            _lbl('इकाई'),
                            const SizedBox(height: 6),
                            _dropdownField(
                              value: _selUnit,
                              items: kUnits,
                              hint: 'चुनें',
                              onChanged: (v) => setState(() {
                                _selUnit = v;
                                if (v != null && v != 'अन्य')
                                  _unitCtrl.text = v;
                                else if (v == 'अन्य') _unitCtrl.text = '';
                                _isDirty = true;
                              }),
                            ),
                            if (_selUnit == 'अन्य') ...[
                              const SizedBox(height: 6),
                              TextField(
                                  controller: _unitCtrl,
                                  onChanged: (_) =>
                                      setState(() => _isDirty = true),
                                  decoration: const InputDecoration(
                                      hintText: 'इकाई लिखें...',
                                      isDense: true)),
                            ],
                          ])),
                    ]),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
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
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
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
                    _lbl('बोलने के नाम'),
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
                          child: const Icon(Icons.add,
                              color: AppColors.primary, size: 20),
                        ),
                      ),
                    ]),
                    if (_aliases.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _aliases
                            .map((a) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: AppColors.border),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.mic,
                                            size: 11,
                                            color: AppColors.textMuted),
                                        const SizedBox(width: 4),
                                        Text(a,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color:
                                                    AppColors.textSecondary)),
                                        const SizedBox(width: 4),
                                        GestureDetector(
                                          onTap: () => setState(
                                              () => _aliases.remove(a)),
                                          child: const Icon(Icons.close,
                                              size: 12,
                                              color: AppColors.textMuted),
                                        ),
                                      ]),
                                ))
                            .toList(),
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
                            '${_lowStockLimit.toInt()} ${_unitCtrl.text.isNotEmpty ? _unitCtrl.text : 'इकाई'}',
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
                        min: 0,
                        max: 100,
                        onChanged: (v) => setState(() {
                          _lowStockLimit = v.roundToDouble();
                          _isDirty = true;
                        }),
                      ),
                    ),
                  ]),

                  const SizedBox(height: 16),

                  // ── Insights ─────────────────────────────────────────────────
                  _section(children: [
                    const Text('इस महीने की जानकारी',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                            letterSpacing: 0.6)),
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
                            value:
                                '${_soldThisMonth % 1 == 0 ? _soldThisMonth.toInt() : _soldThisMonth.toStringAsFixed(1)} ${widget.item.unit}',
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
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5))
                          : const Text('सहेजें',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ), // SingleChildScrollView
            ), // SafeArea
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
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
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
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  // Each item shows "किलो / KG" but value is the canonical Hindi string (#23)
  Widget _dropdownField({
    required String? value,
    required List<UnitCategoryItem> items,
    required String hint,
    required void Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButton<String>(
        value: value,
        hint: Text(hint,
            style: const TextStyle(
                color: Color(0xFFB0BAC8),
                fontSize: 13,
                fontStyle: FontStyle.italic)),
        isExpanded: true,
        underline: const SizedBox.shrink(),
        icon: const Icon(Icons.keyboard_arrow_down,
            color: AppColors.textMuted, size: 18),
        style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500),
        items: items
            .map((e) => DropdownMenuItem(
                value: e.canonical, child: Text(e.dropdownLabel)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _lbl(String t) => Text(t,
      style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary));
}
