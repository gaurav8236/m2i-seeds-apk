import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import 'stock_item_detail_screen.dart';

class InventoryScreen extends StatefulWidget {
  final void Function(VoidCallback) onRegisterReload;
  const InventoryScreen({super.key, required this.onRegisterReload});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl = TabController(length: 2, vsync: this, initialIndex: 1);

  List<StockItem> _stock = [];
  List<MasterItem> _masterInventory = [];
  bool _loading = true;

  // ── Add form ───────────────────────────────────────────────────────────────
  final _nameCtrl     = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _unitCtrl     = TextEditingController();
  final _priceCtrl    = TextEditingController();
  final _stockCtrl    = TextEditingController();
  final _aliasCtrl    = TextEditingController();
  final _nameFocus    = FocusNode();
  double _lowStockLimit = 10;
  List<String> _aliases = [];
  List<dynamic> _suggestions = [];
  bool _showSuggestions = false;
  bool _suppressSuggestions = false;

  // Preview list (items staged before final submit)
  final List<Map<String, dynamic>> _preview = [];
  bool _submitting = false;

  // ── List tab ───────────────────────────────────────────────────────────────
  String _searchQuery = '';
  bool _showLowOnly   = false;

  @override
  void initState() {
    super.initState();
    widget.onRegisterReload(_load);
    _load();
    _nameCtrl.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _nameCtrl
      ..removeListener(_onNameChanged)
      ..dispose();
    _categoryCtrl.dispose();
    _unitCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _aliasCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stock  = await SupabaseService.fetchStock();
      final master = await SupabaseService.fetchMasterInventory();
      setState(() { _stock = stock; _masterInventory = master; });
    } catch (e) {
      _snack('लोड नहीं हो सका: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── Autocomplete ───────────────────────────────────────────────────────────

  void _onNameChanged() {
    if (_suppressSuggestions) return;
    final q = _nameCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() { _suggestions = []; _showSuggestions = false; });
      return;
    }
    final stockMatches  = _stock.where((s) => s.itemName.toLowerCase().contains(q)).toList();
    final stockNames    = stockMatches.map((s) => s.itemName).toSet();
    final masterMatches = _masterInventory
        .where((m) => m.name.toLowerCase().contains(q) && !stockNames.contains(m.name))
        .toList();
    setState(() {
      _suggestions = [...stockMatches, ...masterMatches];
      _showSuggestions = _suggestions.isNotEmpty;
    });
  }

  void _selectStock(StockItem s) {
    _suppressSuggestions = true;
    _nameCtrl.text     = s.itemName;
    _categoryCtrl.text = s.category;
    _unitCtrl.text     = s.unit;
    _priceCtrl.text    = s.sellingPrice.toInt().toString();
    _stockCtrl.text    = s.currentStock.toInt().toString();
    setState(() {
      _lowStockLimit   = s.lowStockLimit;
      _aliases         = List.from(s.aliases);
      _showSuggestions = false;
    });
    _nameFocus.unfocus();
    _suppressSuggestions = false;
  }

  void _selectMaster(MasterItem m) {
    _suppressSuggestions = true;
    _nameCtrl.text     = m.name;
    _categoryCtrl.text = m.category;
    _unitCtrl.text     = m.unit;
    _priceCtrl.clear();
    _stockCtrl.clear();
    setState(() {
      _lowStockLimit   = 10;
      _aliases         = [];
      _showSuggestions = false;
    });
    _nameFocus.unfocus();
    _suppressSuggestions = false;
  }

  // ── Alias chips ────────────────────────────────────────────────────────────

  void _addAlias() {
    final a = _aliasCtrl.text.trim();
    if (a.isNotEmpty && !_aliases.contains(a)) {
      setState(() => _aliases.add(a));
      _aliasCtrl.clear();
    }
  }

  // ── Preview ────────────────────────────────────────────────────────────────

  void _addToPreview() {
    final name  = _nameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text);
    final stock = double.tryParse(_stockCtrl.text);
    if (name.isEmpty || price == null || stock == null) {
      _snack('कृपया नाम, कीमत और स्टॉक भरें');
      return;
    }
    setState(() {
      _preview.add({
        'item_name':       name,
        'category':        _categoryCtrl.text.trim(),
        'unit':            _unitCtrl.text.trim(),
        'selling_price':   price,
        'current_stock':   stock,
        'low_stock_limit': _lowStockLimit,
        'aliases':         List.from(_aliases),
        'cost_price':      0.0,
        'image_url':       null,
      });
      _clearForm();
    });
  }

  void _clearForm() {
    _suppressSuggestions = true;
    _nameCtrl.clear();
    _categoryCtrl.clear();
    _unitCtrl.clear();
    _priceCtrl.clear();
    _stockCtrl.clear();
    _aliasCtrl.clear();
    _lowStockLimit   = 10;
    _aliases         = [];
    _showSuggestions = false;
    _suppressSuggestions = false;
  }

  Future<void> _submitAll() async {
    if (_preview.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await SupabaseService.upsertInventoryItems(List.from(_preview));
      setState(() => _preview.clear());
      await _load();
      _tabCtrl.animateTo(1);
      _snack('सभी आइटम सफलतापूर्वक जोड़े गए!');
    } catch (e) {
      _snack('सेव नहीं हो सका: $e');
    } finally {
      setState(() => _submitting = false);
    }
  }

  // ── Filtered list ──────────────────────────────────────────────────────────

  List<StockItem> get _filtered => _stock.where((s) {
    final q = _searchQuery.toLowerCase();
    return (s.itemName.toLowerCase().contains(q) || s.category.toLowerCase().contains(q))
        && (!_showLowOnly || s.isLow);
  }).toList();

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(children: [
        _header(),
        Expanded(child: TabBarView(
          controller: _tabCtrl,
          children: [_addTab(), _listTab()],
        )),
      ]),
    );
  }

  Widget _header() {
    return Container(
      decoration: BoxDecoration(
        gradient: primaryGradient,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.25)),
                ),
                child: const Icon(Icons.inventory_2, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('इन्वेंट्री प्रबंधन',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                Text('सामान और स्टॉक प्रबंधन',
                    style: TextStyle(color: Colors.white70, fontSize: 10)),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabCtrl,
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: AppColors.primary,
                unselectedLabelColor: Colors.white,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: '+ सामान जोड़ें'),
                  Tab(text: '📦 स्टॉक सूची'),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Tab 1 — Add ────────────────────────────────────────────────────────────

  Widget _addTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _formCard(),
        if (_preview.isNotEmpty) ...[
          const SizedBox(height: 16),
          _previewCard(),
        ],
      ]),
    );
  }

  Widget _formCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Name + autocomplete ──────────────────────────────────────────
        _lbl('सामान का नाम'),
        const SizedBox(height: 4),
        TextField(
          controller: _nameCtrl,
          focusNode: _nameFocus,
          decoration: const InputDecoration(
            hintText: 'उदा. बासमती चावल',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        if (_showSuggestions) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8)],
            ),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: _suggestions.map((s) {
                if (s is StockItem) {
                  return ListTile(
                    dense: true,
                    title: Text(s.itemName,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: Text(
                        '${s.category} · ₹${s.sellingPrice.toInt()} · स्टॉक: ${s.currentStock.toInt()} ${s.unit}',
                        style: const TextStyle(fontSize: 11)),
                    onTap: () => _selectStock(s),
                  );
                }
                final m = s as MasterItem;
                return ListTile(
                  dense: true,
                  leading: Container(width: 3, color: const Color(0xFF93C5FD)),
                  title: Text(m.name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text('${m.category} · ${m.unit} · नया जोड़ें',
                      style: const TextStyle(
                          fontSize: 11, fontStyle: FontStyle.italic, color: AppColors.textMuted)),
                  onTap: () => _selectMaster(m),
                );
              }).toList(),
            ),
          ),
        ],
        const SizedBox(height: 12),

        // ── Category + Unit ──────────────────────────────────────────────
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _lbl('श्रेणी'),
            const SizedBox(height: 4),
            TextField(
              controller: _categoryCtrl,
              decoration: const InputDecoration(
                hintText: 'उदा. अनाज',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ])),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _lbl('इकाई'),
            const SizedBox(height: 4),
            TextField(
              controller: _unitCtrl,
              decoration: const InputDecoration(
                hintText: 'उदा. किलो',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ])),
        ]),
        const SizedBox(height: 12),

        // ── Price + Stock ────────────────────────────────────────────────
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _lbl('बिक्री कीमत (₹)'),
            const SizedBox(height: 4),
            TextField(
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: '0',
                prefixText: '₹ ',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ])),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _lbl('वर्तमान स्टॉक'),
            const SizedBox(height: 4),
            TextField(
              controller: _stockCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: '0',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ])),
        ]),
        const SizedBox(height: 12),

        // ── Aliases ──────────────────────────────────────────────────────
        _lbl('बोलने के नाम'),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _aliasCtrl,
              decoration: const InputDecoration(
                hintText: 'उदा. चावल, बासमती',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
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
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(a, style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => setState(() => _aliases.remove(a)),
                  child: const Icon(Icons.close, size: 14, color: AppColors.primary),
                ),
              ]),
            )).toList(),
          ),
        ],
        const SizedBox(height: 12),

        // ── Low stock slider ─────────────────────────────────────────────
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _lbl('कम स्टॉक चेतावनी'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: Text(
              '${_lowStockLimit.toInt()} ${_unitCtrl.text.isNotEmpty ? _unitCtrl.text : 'इकाई'}',
              style: const TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ]),
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
            onChanged: (v) => setState(() => _lowStockLimit = v.roundToDouble()),
          ),
        ),
        const SizedBox(height: 4),

        // ── Add to preview ───────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _addToPreview,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('समीक्षा सूची में जोड़ें',
                style: TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _previewCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.list_alt, color: AppColors.primary, size: 18),
          const SizedBox(width: 6),
          Text('समीक्षा सूची (${_preview.length})',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.primary)),
        ]),
        const SizedBox(height: 12),
        ..._preview.asMap().entries.map((e) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.value['item_name'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 2),
              Text(
                  '₹${e.value['selling_price']} · स्टॉक: ${e.value['current_stock']} ${e.value['unit'] ?? ''}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ])),
            GestureDetector(
              onTap: () => setState(() => _preview.removeAt(e.key)),
              child: const Icon(Icons.delete_outline, color: AppColors.danger, size: 18),
            ),
          ]),
        )),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _submitting ? null : _submitAll,
            icon: _submitting
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.check, size: 18),
            label: const Text('सभी को स्टॉक में जोड़ें',
                style: TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Tab 2 — List ───────────────────────────────────────────────────────────

  Widget _listTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final filtered  = _filtered;
    final lowCount  = _stock.where((s) => s.isLow).length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Search
          TextField(
            decoration: const InputDecoration(
              hintText: 'आइटम का नाम या श्रेणी खोजें...',
              prefixIcon: Icon(Icons.search, size: 18),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              fillColor: Colors.white,
              filled: true,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 10),

          // Filter chips
          Row(children: [
            _chip('सभी सामान (${_stock.length})', !_showLowOnly,
                () => setState(() => _showLowOnly = false)),
            const SizedBox(width: 8),
            _chip('कम स्टॉक ($lowCount)', _showLowOnly,
                () => setState(() => _showLowOnly = true)),
          ]),
          const SizedBox(height: 12),

          if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: const Column(children: [
                Icon(Icons.inventory_2_outlined, size: 42, color: AppColors.border),
                SizedBox(height: 8),
                Text('कोई स्टॉक आइटम नहीं मिला',
                    style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                SizedBox(height: 4),
                Text('"सामान जोड़ें" टैब का उपयोग करें',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ]),
            )
          else
            ...filtered.map(_stockCard),
        ],
      ),
    );
  }

  Widget _stockCard(StockItem s) {
    final isLow = s.isLow;
    final priceStr = s.sellingPrice % 1 == 0
        ? s.sellingPrice.toInt().toString()
        : s.sellingPrice.toStringAsFixed(2);
    final stockStr = s.currentStock % 1 == 0
        ? s.currentStock.toInt().toString()
        : s.currentStock.toStringAsFixed(1);

    return GestureDetector(
      onTap: () => _openItemDetail(s),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isLow ? const Color(0xFFFFCACA) : AppColors.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1 — name
                  Text(
                    s.itemName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w400, fontSize: 14,
                        color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Row 2 — category · price · stock
                  Row(
                    children: [
                      if (s.category.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            s.category,
                            style: const TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w500,
                                color: Color(0xFF92400E)),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text('₹$priceStr',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary)),
                      const SizedBox(width: 6),
                      Text('·',
                          style: TextStyle(fontSize: 11, color: AppColors.border)),
                      const SizedBox(width: 6),
                      Text(
                        '$stockStr ${s.unit}',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w400,
                            color: isLow ? AppColors.danger : AppColors.textMuted),
                      ),
                      if (isLow) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.dangerLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('कम',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                                  color: AppColors.danger)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.border),
          ],
        ),
      ),
    );
  }

  void _openItemDetail(StockItem s) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StockItemDetailScreen(item: s)),
    ).then((_) => _load());
  }

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? AppColors.primary : AppColors.border),
          boxShadow: active
              ? [BoxShadow(
                  color: AppColors.primary.withOpacity(0.25), blurRadius: 8)]
              : null,
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: active ? Colors.white : AppColors.textSecondary,
            )),
      ),
    );
  }

  Widget _lbl(String t) => Text(t,
      style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary));
}
