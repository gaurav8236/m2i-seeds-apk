import 'dart:async';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../models/models.dart';
import '../services/draft_service.dart';
import '../services/supabase_service.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import '../utils/bill_pdf.dart';
import 'past_bills_screen.dart';
import 'recording_screen.dart';

enum BillingView { input, settlement, success }

class VoiceBillingScreen extends StatefulWidget {
  const VoiceBillingScreen({super.key});

  @override
  State<VoiceBillingScreen> createState() => _VoiceBillingScreenState();
}

class _VoiceBillingScreenState extends State<VoiceBillingScreen> {
  BillingView _view = BillingView.input;
  bool _isProcessing = false;
  List<BillItem> _billItems = [];
  List<StockItem> _stockList = [];
  List<String> _customerNames = [];
  double _discount = 0;
  bool _isCredit = false;
  String _customerName = '';
  double _finalTotal = 0;
  String _currentDraftId = DateTime.now().millisecondsSinceEpoch.toString();
  List<DraftBill> _drafts = [];

  // Settlement
  final _customerController = TextEditingController();
  final _customerFocusNode = FocusNode();
  bool _showCustomerSuggestions = false;

  @override
  void initState() {
    super.initState();
    // Show the customer dropdown as soon as the field is focused, not just
    // once the user starts typing — a short delay on blur lets a tap on a
    // suggestion register before the list disappears.
    _customerFocusNode.addListener(() {
      if (_customerFocusNode.hasFocus) {
        setState(() => _showCustomerSuggestions = true);
      } else {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _showCustomerSuggestions = false);
        });
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _customerController.dispose();
    _customerFocusNode.dispose();
    VoiceService.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        SupabaseService.fetchStock(),
        SupabaseService.fetchCustomerNames(),
        DraftService.loadDrafts(),
      ]);
      if (mounted) setState(() {
        _stockList = results[0] as List<StockItem>;
        _customerNames = results[1] as List<String>;
        _drafts = results[2] as List<DraftBill>;
      });
    } catch (_) {
      if (mounted) _showSnack('डेटा लोड नहीं हो सका, दोबारा कोशिश करें');
    }
  }

  Future<void> _autoSaveDraft() async {
    if (_billItems.isEmpty) return;
    final draft = DraftBill(
      id: _currentDraftId,
      items: List.from(_billItems),
      discount: _discount,
      customerName: _customerName,
      savedAt: DateTime.now(),
    );
    await DraftService.saveDraft(draft);
  }

  void _resumeDraft(DraftBill draft) {
    setState(() {
      _currentDraftId = draft.id;
      _billItems = List.from(draft.items);
      _discount = draft.discount;
      _customerName = draft.customerName;
      _customerController.text = draft.customerName;
      _view = BillingView.input;
    });
  }

  Future<void> _deleteDraft(String id) async {
    await DraftService.deleteDraft(id);
    final drafts = await DraftService.loadDrafts();
    setState(() => _drafts = drafts);
  }

  String _timeSince(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'अभी';
    if (diff.inMinutes < 60) return '${diff.inMinutes} मिनट पहले';
    if (diff.inHours < 24) return '${diff.inHours} घंटे पहले';
    return '${diff.inDays} दिन पहले';
  }

  double get _subTotal => _billItems.fold(0, (s, i) => s + i.itemTotal);
  double get _grandTotal => (_subTotal - _discount).clamp(0, double.infinity);

  String _getUnit(BillItem item) {
    if (item.unit.isNotEmpty) return item.unit;
    final stock = _stockList.firstWhere(
      (s) => s.itemName == item.itemName,
      orElse: () => StockItem(
          id: '', currentStock: 0, sellingPrice: 0, lowStockLimit: 0,
          aliases: [], itemName: '', category: '', unit: ''),
    );
    return stock.unit.isEmpty ? 'इकाई' : stock.unit;
  }

  void _updateItem(int i, {double? qty, double? price}) {
    final items = [..._billItems];
    if (qty != null) items[i].quantity = qty;
    if (price != null) items[i].pricePerUnit = price;
    items[i].itemTotal = items[i].quantity * items[i].pricePerUnit;
    items[i].stockRemaining = items[i].currentStock - items[i].quantity;
    setState(() => _billItems = items);
  }

  void _selectItem(int i, String name) {
    final stock = _stockList.firstWhere(
      (s) => s.itemName == name,
      orElse: () => StockItem(
          id: '', currentStock: 0, sellingPrice: 0, lowStockLimit: 0,
          aliases: [], itemName: '', category: '', unit: ''),
    );
    final items = [..._billItems];
    items[i].itemName = name;
    if (stock.id.isNotEmpty) {
      items[i].pricePerUnit = stock.sellingPrice;
      items[i].stockId = stock.id;
      items[i].currentStock = stock.currentStock;
      items[i].unit = stock.unit;
      items[i].hasError = false;
      items[i].itemTotal = items[i].quantity * items[i].pricePerUnit;
      items[i].stockRemaining = items[i].currentStock - items[i].quantity;
    }
    setState(() => _billItems = items);
  }

  void _removeItem(int i) {
    final items = [..._billItems];
    items.removeAt(i);
    setState(() => _billItems = items);
  }

  void _addBlankItem() {
    setState(() {
      _billItems.add(BillItem(
        itemName: '',
        quantity: 1,
        pricePerUnit: 0,
        itemTotal: 0,
        stockRemaining: 0,
        currentStock: 0,
        unit: '',
      ));
    });
  }

  void _addManualItem() {
    _addBlankItem();
    _showItemPicker(_billItems.length - 1);
  }

  Future<void> _finalizeBill() async {
    setState(() => _isProcessing = true);
    try {
      final validItems = _billItems.where((i) => i.itemName.isNotEmpty).toList();
      final subTotal = validItems.fold(0.0, (s, i) => s + i.itemTotal);
      final finalTotal = (subTotal - _discount).clamp(0.0, double.infinity);

      await SupabaseService.checkout(
        items: validItems.map((i) => i.toMap()).toList(),
        totalAmount: finalTotal,
        discountAmount: _discount,
        customerName: _customerName.isEmpty ? null : _customerName,
        isCredit: _isCredit,
      );

      await DraftService.deleteDraft(_currentDraftId);
      setState(() {
        _finalTotal = finalTotal;
        _view = BillingView.success;
      });
      _currentDraftId = DateTime.now().millisecondsSinceEpoch.toString();
      await _loadData();
    } catch (e) {
      _showSnack('बिल सहेजने में त्रुटि: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _downloadPdf() async {
    try {
      final bytes = await buildBillPdfBytes(
        items: _billItems,
        customerName: _customerName,
        isCredit: _isCredit,
        subTotal: _subTotal,
        discount: _discount,
        grandTotal: _grandTotal,
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (mounted) _showSnack('PDF डाउनलोड में त्रुटि: $e');
    }
  }

  Future<void> _sharePdfOnWhatsApp() async {
    try {
      final bytes = await buildBillPdfBytes(
        items: _billItems,
        customerName: _customerName,
        isCredit: _isCredit,
        subTotal: _subTotal,
        discount: _discount,
        grandTotal: _grandTotal,
      );
      await Printing.sharePdf(bytes: bytes, filename: 'bill.pdf');
    } catch (e) {
      if (mounted) _showSnack('PDF शेयर में त्रुटि: $e');
    }
  }

  void _resetBill() {
    setState(() {
      _view = BillingView.input;
      _billItems = [];
      _discount = 0;
      _isCredit = false;
      _customerName = '';
      _customerController.clear();
      _finalTotal = 0;
    });
  }

  Future<void> _openRecordingScreen() async {
    final results = await Navigator.push<List<BillItem>>(
      context,
      MaterialPageRoute(
        builder: (_) => RecordingScreen(stockList: _stockList),
      ),
    );
    if (!mounted) return;
    if (results != null && results.isNotEmpty) {
      setState(() => _billItems = results);
    }
  }

  Widget _draftCard(DraftBill draft) {
    final subTotal = draft.items.fold(0.0, (s, i) => s + i.itemTotal);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 1.5,
            style: BorderStyle.solid),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('ड्राफ़्ट',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ),
            const SizedBox(width: 8),
            Text(_timeSince(draft.savedAt),
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            const Spacer(),
            GestureDetector(
              onTap: () => _deleteDraft(draft.id),
              child: const Icon(Icons.close, size: 16, color: AppColors.textMuted),
            ),
          ]),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          title: Text(
            draft.customerName.isNotEmpty ? draft.customerName : 'ग्राहक नहीं चुना',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text('${draft.items.length} आइटम · ₹${subTotal.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          trailing: TextButton(
            onPressed: () => _resumeDraft(draft),
            child: const Text('जारी रखें →',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                    color: AppColors.primary)),
          ),
        ),
      ]),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return switch (_view) {
      BillingView.input => _buildInput(),
      BillingView.settlement => _buildSettlement(),
      BillingView.success => _buildSuccess(),
    };
  }

  // ── VIEW 1: INPUT ───────────────────────────────────────────────────────────

  Widget _buildInput() {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          await _autoSaveDraft();
        }
      },
      child: _buildInputScaffold(),
    );
  }

  Widget _buildInputScaffold() {
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
              boxShadow: [BoxShadow(color: const Color(0xFF0D47A1).withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 4))],
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
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          child: const Icon(Icons.receipt_long, color: Colors.white, size: 17),
                        ),
                        const SizedBox(width: 8),
                        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('नया बिल', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                          Text('बिल बनाएं', style: TextStyle(color: Colors.white70, fontSize: 10)),
                        ]),
                      ]),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const PastBillsScreen())),
                        icon: const Icon(Icons.history, size: 14),
                        label: const Text('पुराने बिल', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.primary,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                  // Show total only when items exist
                  if (_billItems.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('कुल राशि',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12, fontWeight: FontWeight.w600)),
                          Text('₹${_grandTotal.toStringAsFixed(0)}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: -0.5)),
                        ],
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                if (_billItems.isEmpty) ...[
                  // Method selection
                  _micZone(),
                  // Draft section below
                  if (_drafts.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('अधूरे बिल',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
                        Text('${_drafts.length} बचे हुए',
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._drafts.map((d) => _draftCard(d)),
                  ],
                  const SizedBox(height: 16),
                ],
                // Bill table
                if (_billItems.isNotEmpty) _billTable(),
                const SizedBox(height: 80),
              ]),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomSheet: (_billItems.isNotEmpty) ? _settleBar() : null,
    );
  }

  Widget _micZone() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('बिल कैसे बनाएं?',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          const Text('एक तरीका चुनें',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 14),
          _methodCard(
            icon: Icons.mic,
            title: 'बोलकर बनाएं',
            subtitle: 'बोलिए — AI बिल खुद तैयार करेगा',
            loading: _isProcessing,
            onTap: _isProcessing ? null : _openRecordingScreen,
          ),
          const SizedBox(height: 12),
          _methodCard(
            icon: Icons.list_alt_outlined,
            title: 'हाथ से बनाएं',
            subtitle: 'आइटम एक-एक करके चुनें',
            onTap: _addManualItem,
          ),
        ],
      ),
    );
  }

  Widget _methodCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
                    )
                  : Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border, width: 2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _billTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('बिल आइटम',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.6)),
                Text('${_billItems.length} आइटम',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          // Column headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: const [
                Expanded(flex: 3, child: Text('आइटम', style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
                Expanded(flex: 2, child: Text('दर (₹)', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
                Expanded(flex: 2, child: Text('मात्रा', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
                Expanded(flex: 2, child: Text('कुल (₹)', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          // Items
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: _billItems.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
            itemBuilder: (_, i) => _billRow(i),
          ),

          // Add item
          const Divider(height: 1, color: AppColors.border),
          TextButton.icon(
            onPressed: _addBlankItem,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('आइटम जोड़ें', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),

          // Discount
          const Divider(height: 1, color: AppColors.border),
          _discountSection(),
        ],
      ),
    );
  }

  Widget _billRow(int i) {
    final item = _billItems[i];
    final priceStr = item.pricePerUnit % 1 == 0
        ? item.pricePerUnit.toInt().toString()
        : item.pricePerUnit.toStringAsFixed(1);
    final qtyStr = item.quantity % 1 == 0
        ? item.quantity.toInt().toString()
        : item.quantity.toStringAsFixed(1);

    return Container(
      color: item.hasError ? AppColors.dangerLight : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Item name
          Expanded(
            flex: 3,
            child: GestureDetector(
              onTap: () => _showItemPicker(i),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.itemName.isEmpty ? 'आइटम का नाम' : item.itemName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: item.itemName.isEmpty ? AppColors.textMuted : AppColors.textPrimary,
                    ),
                  ),
                  if (item.itemName.isNotEmpty)
                    Text('₹/${_getUnit(item)}',
                        style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                ],
              ),
            ),
          ),

          // Price — tappable
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () => _showNumberPad(i, isPrice: true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(priceStr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ),
            ),
          ),

          // Quantity — tappable
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () => _showNumberPad(i, isPrice: false),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(qtyStr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ),
            ),
          ),

          // Total + delete
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('₹${item.itemTotal.toStringAsFixed(0)}',
                    style: const TextStyle(fontWeight: FontWeight.w700,
                        color: AppColors.primary, fontSize: 13)),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _removeItem(i),
                  child: const Icon(Icons.delete_outline, size: 16, color: AppColors.danger),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showNumberPad(int itemIndex, {required bool isPrice}) {
    final item = _billItems[itemIndex];
    final currentValue = isPrice ? item.pricePerUnit : item.quantity;
    String input = currentValue % 1 == 0
        ? currentValue.toInt().toString()
        : currentValue.toStringAsFixed(1);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
              // Sticky item row
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.itemName,
                          style: const TextStyle(fontWeight: FontWeight.w700,
                              fontSize: 14, color: AppColors.textPrimary)),
                      Text(isPrice ? 'दर बदलें' : 'मात्रा बदलें',
                          style: const TextStyle(fontSize: 11, color: AppColors.primary,
                              fontWeight: FontWeight.w500)),
                    ]),
                  ),
                  Text('₹${item.itemTotal.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w700,
                          fontSize: 15, color: AppColors.primary)),
                ]),
              ),
              // Display
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                  ),
                  child: Center(
                    child: Text(
                      isPrice ? '₹$input' : input,
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary, letterSpacing: -1),
                    ),
                  ),
                ),
              ),
              // Keypad
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    for (final row in [
                      ['7', '8', '9'],
                      ['4', '5', '6'],
                      ['1', '2', '3'],
                      ['.', '0', '⌫'],
                    ])
                      Row(
                        children: row.map((key) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: GestureDetector(
                              onTap: () => setModal(() {
                                if (key == '⌫') {
                                  if (input.length > 1) {
                                    input = input.substring(0, input.length - 1);
                                  } else {
                                    input = '0';
                                  }
                                } else if (key == '.' && input.contains('.')) {
                                  // ignore
                                } else {
                                  input = (input == '0' && key != '.') ? key : input + key;
                                }
                              }),
                              child: Container(
                                height: 52,
                                decoration: BoxDecoration(
                                  color: key == '⌫' ? AppColors.dangerLight : AppColors.bg,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Center(
                                  child: Text(key,
                                      style: TextStyle(
                                          fontSize: key == '⌫' ? 18 : 20,
                                          fontWeight: FontWeight.w600,
                                          color: key == '⌫' ? AppColors.danger : AppColors.textPrimary)),
                                ),
                              ),
                            ),
                          ),
                        )).toList(),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // Confirm
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      final val = double.tryParse(input) ?? 0;
                      if (isPrice) {
                        _updateItem(itemIndex, price: val);
                      } else {
                        _updateItem(itemIndex, qty: val.clamp(0.1, double.infinity));
                      }
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('ठीक है',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showItemPicker(int index) {
    final controller = TextEditingController(text: _billItems[index].itemName);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: DraggableScrollableSheet(
          expand: false,
          maxChildSize: 0.7,
          builder: (_, scrollCtrl) => StatefulBuilder(
            builder: (ctx, setModal) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'आइटम खोजें...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setModal(() {}),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    children: _stockList
                        .where((s) => s.itemName.toLowerCase().contains(controller.text.toLowerCase()))
                        .map((s) => ListTile(
                              title: Text(s.itemName, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('₹${s.sellingPrice} / ${s.unit}  •  स्टॉक: ${s.currentStock}'),
                              onTap: () {
                                _selectItem(index, s.itemName);
                                Navigator.pop(ctx);
                              },
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  Widget _discountSection() {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('छूट',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textSecondary)),
              SizedBox(
                width: 100,
                child: TextField(
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    prefixText: '₹',
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _discount = double.tryParse(v) ?? 0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [10, 20, 50, 100].map((amt) => GestureDetector(
              onTap: () => setState(() => _discount = amt.toDouble()),
              child: Chip(
                label: Text('-₹$amt', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                backgroundColor: AppColors.surface2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: AppColors.border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _settleBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${_billItems.length} आइटम',
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                Text('कुल: ₹${_grandTotal.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _view = BillingView.settlement),
                icon: const Icon(Icons.receipt_long),
                label: const Text('बिल सेटल करें →', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── VIEW 2: SETTLEMENT ──────────────────────────────────────────────────────

  Widget _buildSettlement() {
    final suggestions = _customerNames
        .where((n) => n.toLowerCase().contains(_customerController.text.toLowerCase()))
        .toList();

    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            decoration: BoxDecoration(
              gradient: primaryGradient,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(children: [
                  Row(children: [
                    IconButton(
                      onPressed: () => setState(() => _view = BillingView.input),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('बिल सेटलमेंट', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                      Text('भुगतान की जानकारी भरें', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ]),
                  ]),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Column(children: [
                      const Text('कुल राशि', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('₹${_grandTotal.toStringAsFixed(0)}',
                          style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1)),
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
                // Bill summary
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('बिल विवरण',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.6)),
                      ),
                    ),
                    ..._billItems.asMap().entries.map((e) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: RichText(
                                text: TextSpan(
                                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                                  children: [
                                    TextSpan(text: e.value.itemName, style: const TextStyle(fontWeight: FontWeight.w500)),
                                    TextSpan(text: ' × ${e.value.quantity}', style: const TextStyle(color: AppColors.textMuted)),
                                  ],
                                ),
                              )),
                              Text('₹${e.value.itemTotal.toStringAsFixed(0)}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            ],
                          ),
                        )),
                    if (_discount > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('छूट', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
                            Text('-₹${_discount.toStringAsFixed(0)}',
                                style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 16),

                // Payment settings
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(children: [
                    // Credit toggle
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('उधार पर?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          Text('ग्राहक अभी भुगतान नहीं करेगा', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        ]),
                        Switch(
                          value: _isCredit,
                          onChanged: (v) => setState(() => _isCredit = v),
                          activeThumbColor: AppColors.primary,
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    // Customer name
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ग्राहक का नाम', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.4)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _customerController,
                          focusNode: _customerFocusNode,
                          decoration: const InputDecoration(
                            hintText: 'खोजें या नया नाम लिखें...',
                          ),
                          onChanged: (v) => setState(() => _customerName = v),
                        ),
                        if (_showCustomerSuggestions)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            constraints: const BoxConstraints(maxHeight: 220),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: suggestions.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      'कोई मौजूदा ग्राहक नहीं मिला — नया ग्राहक जोड़ा जाएगा',
                                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                    ),
                                  )
                                : ListView(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    children: suggestions.map((name) => ListTile(
                                      dense: true,
                                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                      onTap: () {
                                        _customerController.text = name;
                                        setState(() {
                                          _customerName = name;
                                          _showCustomerSuggestions = false;
                                        });
                                        _customerFocusNode.unfocus();
                                      },
                                    )).toList(),
                                  ),
                          ),
                      ],
                    ),
                  ]),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _finalizeBill,
                    icon: _isProcessing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : const Icon(Icons.check_circle_outline),
                    label: Text(_isProcessing ? 'प्रोसेस हो रहा है...' : 'बिल पक्का करें',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── VIEW 3: SUCCESS ─────────────────────────────────────────────────────────

  Widget _buildSuccess() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF064E3B), Color(0xFF059669)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                child: Column(children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.2),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
                    ),
                    child: const Icon(Icons.check_circle_outline, color: Colors.white, size: 38),
                  ),
                  const SizedBox(height: 16),
                  const Text('बिल पक्का हो गया!',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22)),
                  const SizedBox(height: 4),
                  const Text('बिल सफलतापूर्वक सहेजा गया',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Column(children: [
                      const Text('कुल राशि', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                      Text('₹${_finalTotal.toStringAsFixed(0)}',
                          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -1)),
                      if (_customerName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${_isCredit ? "🔴 उधार" : "🟢 नकद"} — $_customerName',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                        ),
                      ],
                    ]),
                  ),
                ]),
              ),
            ),
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _downloadPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('PDF डाउनलोड', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: AppColors.borderStrong),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _sharePdfOnWhatsApp,
                    icon: const Icon(Icons.share_outlined, color: Color(0xFF25D366)),
                    label: const Text('WhatsApp पर शेयर करें',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Color(0xFF25D366))),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: const BorderSide(color: Color(0xFF25D366)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _resetBill,
                    icon: const Icon(Icons.mic),
                    label: const Text('नया बिल बनाएं', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
