import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
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

  late final _nameCtrl = TextEditingController(text: widget.item.itemName);
  late final _categoryCtrl = TextEditingController(text: widget.item.category);
  late final _unitCtrl = TextEditingController(text: widget.item.unit);
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

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _unitCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _aliasCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInsights() async {
    if (widget.item.id.isEmpty) return;
    try {
      final results = await Future.wait([
        SupabaseService.fetchItemSalesThisMonth(widget.item.id),
        SupabaseService.fetchLastRestock(widget.item.id),
      ]);
      if (mounted) setState(() {
        _soldThisMonth = results[0] as double;
        _lastRestock = results[1] as StockHistoryEntry?;
        _insightsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _insightsLoading = false);
    }
  }

  Future<void> _save() async {
    final nameErr = Validators.itemName(_nameCtrl.text);
    final priceErr = Validators.sellingPrice(_priceCtrl.text);
    final stockErr = Validators.currentStock(_stockCtrl.text);
    final firstErr = nameErr ?? priceErr ?? stockErr;
    if (firstErr != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(firstErr)));
      return;
    }
    final name     = _nameCtrl.text.trim();
    final price    = double.parse(_priceCtrl.text.trim());
    final newStock = double.parse(_stockCtrl.text.trim());

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

      // Use ID-based direct update instead of the name-keyed upsert RPC.
      // The RPC creates a new item when the name changes (#22); this path
      // updates the existing row correctly, and also avoids the RPC error
      // seen after logRestock (#20).
      await SupabaseService.updateInventoryItem(
        stockId: widget.item.id,
        itemName: name,
        category: _categoryCtrl.text.trim(),
        unit: _unitCtrl.text.trim(),
        sellingPrice: price,
        currentStock: newStock,
        lowStockLimit: _lowStockLimit,
        aliases: _aliases,
      );

      if (mounted) {
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

  void _addAlias() {
    final a = _aliasCtrl.text.trim();
    if (a.isNotEmpty && !_aliases.contains(a)) {
      setState(() => _aliases.add(a));
      _aliasCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
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
                    decoration: const InputDecoration(isDense: true)),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _lbl('श्रेणी'),
                    const SizedBox(height: 6),
                    TextField(controller: _categoryCtrl,
                        decoration: const InputDecoration(
                            hintText: 'अनाज', isDense: true)),
                  ])),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _lbl('इकाई'),
                    const SizedBox(height: 6),
                    TextField(controller: _unitCtrl,
                        decoration: const InputDecoration(
                            hintText: 'किलो', isDense: true)),
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
                    min: 0, max: 100,
                    onChanged: (v) =>
                        setState(() => _lowStockLimit = v.roundToDouble()),
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
    );
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _lbl(String t) => Text(t,
      style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary));
}
