import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import '../design_system/components/confirm_dialog.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/draft_service.dart';
import '../services/supabase_service.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import '../utils/analytics.dart';
import '../utils/bill_pdf.dart';
import 'past_bills_screen.dart';
import 'recording_screen.dart';

enum BillingView { input, settlement, success }

class VoiceBillingScreen extends StatefulWidget {
  final void Function(VoidCallback) onRegisterReload;

  // Test-only seam: when provided, _loadData() seeds _stockList from this
  // directly and skips the Supabase network fetch entirely, so widget tests
  // can exercise the item-picker's real selection flow (BUG-5b) against
  // known stock data instead of an always-empty list. Never set in
  // production code — default null preserves existing behavior exactly.
  @visibleForTesting
  final List<StockItem>? initialStockForTest;

  // Test-only seam: when provided, seeds `_billItems` directly in
  // `initState()`, bypassing the manual-add UI/modal flow entirely. Added
  // for BUG-5a (`.claude/qa/BUGS.md`, back-navigation crash) so a widget
  // test can get `_autoSaveDraft()` past its `_billItems.isEmpty` early
  // return (and therefore into its real `await DraftService.saveDraft(...)`
  // async gap) without depending on `_addManualItem()`'s own modal
  // machinery, which is BUG-5b's unrelated code path. Never set in
  // production code — default null preserves existing behavior exactly.
  @visibleForTesting
  final List<BillItem>? initialBillItemsForTest;

  const VoiceBillingScreen({
    super.key,
    required this.onRegisterReload,
    this.initialStockForTest,
    this.initialBillItemsForTest,
  });

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
  bool _isSplit = false;
  final _nagadCtrl = TextEditingController();
  String _customerName = '';
  double _finalTotal = 0;
  String _currentDraftId = DateTime.now().millisecondsSinceEpoch.toString();
  List<DraftBill> _drafts = [];
  String _shopName = '';

  // BUG-5b instrumentation (`.claude/qa/BUGS.md`,
  // `.claude/records/2026-09-13-bug5-architecture-review.md`). A
  // `flutter_test` double-tap widget test (`test/voice_billing_screen_test.dart`)
  // did NOT reproduce the crash against this code, so the Architect's
  // primary "overlapping _addManualItem() calls" hypothesis is unconfirmed
  // — no reentrancy guard has been applied. These counters are lightweight,
  // no-op-cost-when-unused production logging only: if BUG-5b recurs on a
  // real device, `adb logcat` timestamps on these two lines will show
  // directly whether two calls actually overlapped within the same
  // pending-frame window, turning "did the race actually happen" from a
  // guess into a fact. Remove once BUG-5b is confirmed one way or another.
  int _manualAddCallSeq = 0;
  int _showItemPickerCallSeq = 0;

  // BUG-5a instrumentation (`.claude/qa/BUGS.md`,
  // `.claude/records/2026-09-13-bug5-architecture-review.md`). Same
  // pattern as the BUG-5b counters above: a `flutter_test` widget test
  // firing two overlapping back-navigation attempts while this screen's
  // own `PopScope` callback below was still awaiting `_autoSaveDraft()`
  // confirmed the overlapping-call sequencing is real (both calls fire,
  // in order) but did NOT reproduce the `_dependents.isEmpty` assertion —
  // the working theory (Android's OS-level predictive-back preview
  // animation starting then being cancelled) needs real device/engine
  // timing a synthetic, single-threaded pump loop can't drive. These
  // counters are lightweight, no-op-cost-when-unused production logging
  // only: if BUG-5a recurs live, `adb logcat` timestamps here and on
  // `app.dart`'s matching `[BUG-5a]` line will show directly whether the
  // shell-level and screen-level `PopScope` callbacks overlapped, and in
  // what order — the "what action preceded it" question this bug has been
  // stuck on. Remove once BUG-5a is confirmed one way or another.
  int _autoSaveDraftCallSeq = 0;
  int _inputPopInvokedCallSeq = 0;

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
    widget.onRegisterReload(_maybeRefreshOnTabSwitch);
    if (widget.initialBillItemsForTest != null) {
      // Test-only path — see the field's doc comment.
      _billItems = List.from(widget.initialBillItemsForTest!);
    }
    _loadData();
  }

  @override
  void dispose() {
    _customerController.dispose();
    _customerFocusNode.dispose();
    _nagadCtrl.dispose();
    VoiceService.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (widget.initialStockForTest != null) {
      // Test-only path — see the field's doc comment.
      setState(() => _stockList = widget.initialStockForTest!);
      return;
    }
    try {
      final results = await Future.wait([
        SupabaseService.fetchStock(),
        SupabaseService.fetchCustomerNames(),
        DraftService.loadDrafts(),
        AuthService.fetchProfile(),
      ]);
      if (!mounted) return;
      setState(() {
        _stockList = results[0] as List<StockItem>;
        _customerNames = results[1] as List<String>;
        _drafts = results[2] as List<DraftBill>;
        final profile = results[3] as Map<String, String?>;
        _shopName = profile['shop_name'] ?? '';
      });
    } catch (e, stack) {
      debugPrint('[VoiceBillingScreen] _loadData error: $e\n$stack');
      if (mounted) _showSnack('डेटा लोड नहीं हो सका, दोबारा कोशिश करें');
    }
  }

  // Cross-tab freshness fix: an item/customer added on another tab wasn't
  // visible here until app restart, since this screen (kept alive inside
  // AppShell's IndexedStack) only ever fetched once, in initState. Only
  // _stockList/_customerNames are genuinely stale across tabs — _drafts and
  // _shopName are written solely by this same live screen instance, so
  // they're excluded to avoid unnecessary refetches on every tab switch.
  Future<void> _refreshStockAndCustomers() async {
    try {
      final results = await Future.wait([
        SupabaseService.fetchStock(),
        SupabaseService.fetchCustomerNames(),
      ]);
      if (!mounted) return;
      setState(() {
        _stockList = results[0] as List<StockItem>;
        _customerNames = results[1] as List<String>;
      });
    } catch (e, stack) {
      debugPrint('[VoiceBillingScreen] _refreshStockAndCustomers error: $e\n$stack');
      // Non-fatal — silently keep the existing list rather than interrupt
      // the user with a snackbar for a background refresh.
    }
  }

  // Gate the tab-switch refresh so it never resets state out from under a
  // user mid-checkout — settlement/success views don't render _stockList/
  // _customerNames at all, so skipping the refresh there loses nothing
  // visible, and the existing post-checkout _loadData() call (below)
  // already covers freshness once they're done.
  void _maybeRefreshOnTabSwitch() {
    if (_view != BillingView.input || _isProcessing) return;
    _refreshStockAndCustomers();
  }

  Future<void> _autoSaveDraft() async {
    // BUG-5a instrumentation — see field doc above.
    final seq = ++_autoSaveDraftCallSeq;
    debugPrint('[BUG-5a] _autoSaveDraft call #$seq start at '
        '${DateTime.now().toIso8601String()}, _billItems.length=${_billItems.length}');
    if (_billItems.isEmpty) return;
    final draft = DraftBill(
      id: _currentDraftId,
      items: List.from(_billItems),
      discount: _discount,
      customerName: _customerName,
      savedAt: DateTime.now(),
    );
    await DraftService.saveDraft(draft);
    Analytics.billDraftSaved();
    debugPrint('[BUG-5a] _autoSaveDraft call #$seq done at '
        '${DateTime.now().toIso8601String()}');
  }

  void _resumeDraft(DraftBill draft) {
    Analytics.billDraftResumed();
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
          id: '',
          currentStock: 0,
          sellingPrice: 0,
          lowStockLimit: 0,
          aliases: [],
          itemName: '',
          category: '',
          unit: ''),
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
          id: '',
          currentStock: 0,
          sellingPrice: 0,
          lowStockLimit: 0,
          aliases: [],
          itemName: '',
          category: '',
          unit: ''),
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
    Analytics.billItemRemoved();
    final items = [..._billItems];
    items.removeAt(i);
    final newSubTotal = items.fold(0.0, (s, item) => s + item.itemTotal);
    setState(() {
      _billItems = items;
      // Reset discount when the new subtotal drops below it (#34)
      if (_discount > newSubTotal) _discount = 0;
    });
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
    // BUG-5b instrumentation — see field doc above.
    final seq = ++_manualAddCallSeq;
    debugPrint('[BUG-5b] _addManualItem call #$seq at '
        '${DateTime.now().toIso8601String()}, _billItems.length=${_billItems.length}');
    Analytics.billItemAddedManual();
    _addBlankItem();
    // Defer to the next frame — _addBlankItem()'s setState() only schedules
    // a rebuild, it doesn't run one synchronously. Opening the item-picker
    // modal immediately, before that rebuild has actually completed, races
    // the framework's element/dependents bookkeeping (suspected cause of
    // BUG-5's "'_dependents.isEmpty': is not true" crash — see
    // .claude/qa/BUGS.md). addPostFrameCallback guarantees the pending
    // rebuild has settled before the new route is pushed.
    final index = _billItems.length - 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showItemPicker(index);
    });
  }

  Future<void> _finalizeBill() async {
    // ── Pre-flight validations ────────────────────────────────────────────────
    // Business rule: a credit (उधार) bill must be tied to a named customer so
    // that repayment can be tracked in their ledger.
    if (_isCredit && _customerName.trim().isEmpty) {
      _showSnack('उधार बिल के लिए ग्राहक का नाम ज़रूरी है');
      return;
    }

    // Discount must not exceed the effective subtotal (bug #54)
    final validSubTotal = _billItems
        .where((i) => i.itemName.isNotEmpty && !i.hasError)
        .fold(0.0, (s, i) => s + i.itemTotal);
    if (_discount > validSubTotal && validSubTotal > 0) {
      _showSnack(
          'छूट ₹${_discount.toStringAsFixed(0)} कुल राशि ₹${validSubTotal.toStringAsFixed(0)} से अधिक है');
      return;
    }
    // ─────────────────────────────────────────────────────────────────────────

    setState(() => _isProcessing = true);
    try {
      // Exclude error items (unrecognised voice results with stockId=null / price=0)
      // to prevent null constraint violations in the checkout API (bug #33 follow-on).
      final validItems = _billItems
          .where((i) => i.itemName.isNotEmpty && !i.hasError)
          .toList();
      final subTotal = validItems.fold(0.0, (s, i) => s + i.itemTotal);
      final finalTotal = (subTotal - _discount).clamp(0.0, double.infinity);

      final nagad = _isSplit
          ? (double.tryParse(_nagadCtrl.text) ?? 0)
              .clamp(0, finalTotal)
              .toDouble()
          : 0.0;
      await SupabaseService.checkout(
        items: validItems.map((i) => i.toMap()).toList(),
        totalAmount: finalTotal,
        discountAmount: _discount,
        customerName: _customerName.isEmpty ? null : _customerName,
        isCredit: _isCredit,
        nagadAmount: nagad,
      );

      Analytics.billConfirmed(
        totalAmount: finalTotal,
        isCredit: _isCredit,
        itemCount: validItems.length,
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
        context: context,
        items: _billItems,
        customerName: _customerName,
        isCredit: _isCredit,
        subTotal: _subTotal,
        discount: _discount,
        grandTotal: _grandTotal,
        shopName: _shopName,
      );
      Analytics.billPdfDownloaded();
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (mounted) _showSnack('PDF डाउनलोड में त्रुटि: $e');
    }
  }

  Future<void> _sharePdfOnWhatsApp() async {
    try {
      final bytes = await buildBillPdfBytes(
        context: context,
        items: _billItems,
        customerName: _customerName,
        isCredit: _isCredit,
        subTotal: _subTotal,
        discount: _discount,
        grandTotal: _grandTotal,
        shopName: _shopName,
      );
      Analytics.billPdfShared();
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
      _isSplit = false;
      _nagadCtrl.clear();
      _customerName = '';
      _customerController.clear();
      _finalTotal = 0;
    });
  }

  Future<void> _cancelBill() async {
    if (_billItems.isEmpty) return;
    final confirmed = await AppDialogs.confirm(
      context,
      title: 'बिल रद्द करें?',
      message: 'इस बिल की सभी आइटम हट जाएँगी। यह वापस नहीं हो सकता।',
      confirmLabel: 'हाँ, रद्द करें',
      cancelLabel: 'नहीं',
      isDangerous: true,
    );
    if (!confirmed) return;
    Analytics.billCancelled(itemCount: _billItems.length);
    await DraftService.deleteDraft(_currentDraftId);
    final drafts = await DraftService.loadDrafts();
    if (!mounted) return;
    _resetBill();
    setState(() {
      _currentDraftId = DateTime.now().millisecondsSinceEpoch.toString();
      _drafts = drafts;
    });
  }

  Future<void> _openRecordingScreen() async {
    Analytics.voiceSessionOpened();
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
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.4),
            width: 1.5,
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
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ),
            const SizedBox(width: 8),
            Text(_timeSince(draft.savedAt),
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            const Spacer(),
            GestureDetector(
              onTap: () => _deleteDraft(draft.id),
              child:
                  const Icon(Icons.close, size: 16, color: AppColors.textMuted),
            ),
          ]),
        ),
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          title: Text(
            draft.customerName.isNotEmpty
                ? draft.customerName
                : 'ग्राहक नहीं चुना',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
              '${draft.items.length} आइटम · ₹${subTotal.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          trailing: TextButton(
            onPressed: () => _resumeDraft(draft),
            child: const Text('जारी रखें →',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
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
        // BUG-5a instrumentation — see field doc above.
        final seq = ++_inputPopInvokedCallSeq;
        debugPrint('[BUG-5a] _buildInput.onPopInvokedWithResult call #$seq at '
            '${DateTime.now().toIso8601String()}, didPop=$didPop');
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
              boxShadow: [
                BoxShadow(
                    color: AppColors.primaryDark.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 4))
              ],
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
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          child: const Icon(Icons.receipt_long,
                              color: Colors.white, size: 17),
                        ),
                        const SizedBox(width: 8),
                        const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('नया बिल',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                              Text('बिल बनाएं',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 10)),
                            ]),
                      ]),
                      Row(children: [
                        if (_billItems.isNotEmpty) ...[
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3)),
                            ),
                            child: IconButton(
                              onPressed: _cancelBill,
                              icon: const Icon(Icons.close,
                                  color: Colors.white, size: 18),
                              tooltip: 'बिल रद्द करें',
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        ElevatedButton.icon(
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const PastBillsScreen())),
                          icon: const Icon(Icons.history, size: 14),
                          label: const Text('पुराने बिल',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ]),
                    ],
                  ),
                  // Show total only when items exist
                  if (_billItems.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('कुल राशि',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          Text('₹${_grandTotal.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 22,
                                  letterSpacing: -0.5)),
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
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: AppColors.textPrimary)),
                        Text('${_drafts.length} बचे हुए',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textMuted)),
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
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('बिल कैसे बनाएं?',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppColors.textPrimary)),
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
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: AppColors.primary),
                    )
                  : Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 22,
              height: 22,
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
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)
        ],
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
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted,
                        letterSpacing: 0.6)),
                Text('${_billItems.length} आइटम',
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          // Column headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: const [
                Expanded(
                    flex: 3,
                    child: Text('आइटम',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600))),
                Expanded(
                    flex: 2,
                    child: Text('दर (₹)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600))),
                Expanded(
                    flex: 2,
                    child: Text('मात्रा',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600))),
                Expanded(
                    flex: 2,
                    child: Text('कुल (₹)',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600))),
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
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.border),
            itemBuilder: (_, i) => _billRow(i),
          ),

          // Add item
          const Divider(height: 1, color: AppColors.border),
          TextButton.icon(
            onPressed: _addBlankItem,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('आइटम जोड़ें',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
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

    // Stock warning: item found but qty exceeds available stock (bug #33)
    final bool hasStockWarning = !item.hasError &&
        item.itemName.isNotEmpty &&
        item.currentStock > 0 &&
        item.quantity > item.currentStock;
    final bool isOutOfStock =
        !item.hasError && item.itemName.isNotEmpty && item.currentStock <= 0;

    return Container(
      color: item.hasError
          ? AppColors.dangerLight
          : (hasStockWarning || isOutOfStock)
              ? AppColors.warningLight // distinct from red (not-found)
              : null,
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
                      color: item.itemName.isEmpty
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (item.itemName.isNotEmpty &&
                      !hasStockWarning &&
                      !isOutOfStock)
                    Text('₹/${_getUnit(item)}',
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.textMuted)),
                  if (isOutOfStock)
                    const Text('⚠️ स्टॉक खत्म',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.warning,
                            fontWeight: FontWeight.w600)),
                  if (hasStockWarning)
                    Text('⚠️ सिर्फ ${item.currentStock.toInt()} बचे',
                        style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.warning,
                            fontWeight: FontWeight.w600)),
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
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
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
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
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
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        fontSize: 13)),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _removeItem(i),
                  child: const Icon(Icons.delete_outline,
                      size: 16, color: AppColors.danger),
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
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
              // Sticky item row
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.itemName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: AppColors.textPrimary)),
                          Text(isPrice ? 'दर बदलें' : 'मात्रा बदलें',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w500)),
                        ]),
                  ),
                  Text('₹${item.itemTotal.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.primary)),
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
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.4)),
                  ),
                  child: Center(
                    child: Text(
                      isPrice ? '₹$input' : input,
                      style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -1),
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
                        children: row
                            .map((key) => Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: GestureDetector(
                                      onTap: () => setModal(() {
                                        if (key == '⌫') {
                                          if (input.length > 1) {
                                            input = input.substring(
                                                0, input.length - 1);
                                          } else {
                                            input = '0';
                                          }
                                        } else if (key == '.' &&
                                            input.contains('.')) {
                                          // ignore
                                        } else {
                                          input = (input == '0' && key != '.')
                                              ? key
                                              : input + key;
                                        }
                                      }),
                                      child: Container(
                                        height: 52,
                                        decoration: BoxDecoration(
                                          color: key == '⌫'
                                              ? AppColors.dangerLight
                                              : AppColors.bg,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                              color: AppColors.border),
                                        ),
                                        child: Center(
                                          child: Text(key,
                                              style: TextStyle(
                                                  fontSize:
                                                      key == '⌫' ? 18 : 20,
                                                  fontWeight: FontWeight.w600,
                                                  color: key == '⌫'
                                                      ? AppColors.danger
                                                      : AppColors.textPrimary)),
                                        ),
                                      ),
                                    ),
                                  ),
                                ))
                            .toList(),
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
                        _updateItem(itemIndex,
                            qty: val.clamp(0.1, double.infinity));
                      }
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('ठीक है',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
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
    // BUG-5b instrumentation — see field doc above.
    final seq = ++_showItemPickerCallSeq;
    debugPrint('[BUG-5b] _showItemPicker call #$seq at '
        '${DateTime.now().toIso8601String()}, index=$index, _billItems.length=${_billItems.length}');
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
                        .where((s) => s.itemName
                            .toLowerCase()
                            .contains(controller.text.toLowerCase()))
                        .map((s) => ListTile(
                              title: Text(s.itemName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  '₹${s.sellingPrice} / ${s.unit}  •  स्टॉक: ${s.currentStock}'),
                              onTap: () {
                                // BUG-5b (confirmed root cause, see
                                // .claude/qa/BUGS.md): popping this sheet
                                // and calling _selectItem() (which
                                // setState()s the screen underneath)
                                // synchronously in the same handler races
                                // the sheet's own teardown — including its
                                // local search-field controller's
                                // .whenComplete(controller.dispose) — against
                                // the parent rebuild and the pop's own
                                // closing transition. Pop first (closes
                                // immediately, as the user expects, and lets
                                // the sheet's teardown run on its own
                                // schedule), then defer the state update to
                                // the next frame, after that teardown has
                                // settled.
                                Navigator.pop(ctx);
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (mounted) _selectItem(index, s.itemName);
                                });
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
    ).whenComplete(() {
      // Defer disposal past the sheet's own closing-transition frame — see
      // the onTap comment above for the full BUG-5b mechanism.
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    });
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
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.textSecondary)),
              SizedBox(
                width: 100,
                child: TextField(
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    prefixText: '₹',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    isDense: true,
                  ),
                  // Restrict to digits and one decimal point (#35).
                  // Clamp to 0 — negative discount increases total (#53).
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                  onChanged: (v) {
                    final n = double.tryParse(v);
                    if (v.isNotEmpty && n == null)
                      return; // silently ignore junk
                    setState(
                        () => _discount = (n ?? 0).clamp(0, double.infinity));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [10, 20, 50, 100]
                .map((amt) => GestureDetector(
                      onTap: () => setState(() => _discount = amt.toDouble()),
                      child: Chip(
                        label: Text('-₹$amt',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                        backgroundColor: AppColors.surface2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                    ))
                .toList(),
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
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600)),
                Text('कुल: ₹${_grandTotal.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Check for stock issues before proceeding (bug #33)
                  final stockIssues = _billItems
                      .asMap()
                      .entries
                      .where((e) =>
                          !e.value.hasError &&
                          e.value.itemName.isNotEmpty &&
                          (e.value.currentStock <= 0 ||
                              e.value.quantity > e.value.currentStock))
                      .toList();

                  if (stockIssues.isNotEmpty) {
                    _showStockWarningSheet();
                  } else {
                    // Refresh customer names in the background so the settlement
                    // dropdown includes customers added since this screen loaded (bug #46).
                    SupabaseService.fetchCustomerNames().then((names) {
                      if (mounted) setState(() => _customerNames = names);
                    }).catchError((_) {
                      // Network failure during refresh is non-fatal — existing list remains.
                    });
                    Analytics.billProceedCheckout(itemCount: _billItems.length);
                    setState(() => _view = BillingView.settlement);
                  }
                },
                icon: const Icon(Icons.receipt_long),
                label: const Text('बिल सेटल करें →',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Stock warning sheet ─────────────────────────────────────────────────────

  // No parameter — issues are recomputed live from _billItems inside the sheet.
  void _showStockWarningSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          // Rebuild live from _billItems so indices stay fresh after each removal/update.
          final live = _billItems
              .asMap()
              .entries
              .where((e) =>
                  !e.value.hasError &&
                  e.value.itemName.isNotEmpty &&
                  (e.value.currentStock <= 0 ||
                      e.value.quantity > e.value.currentStock))
              .toList();

          final allFixed = live.isEmpty;

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),

                if (allFixed) ...[
                  // ── All-clear state ──────────────────────────────────────────
                  const SizedBox(height: 8),
                  Center(
                    child: Column(children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(
                          color: AppColors.successLight,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_circle_outline,
                            color: AppColors.success, size: 30),
                      ),
                      const SizedBox(height: 12),
                      const Text('सभी आइटम ठीक हो गए',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.success)),
                      const SizedBox(height: 4),
                      const Text('अब बिल सेटल कर सकते हैं',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textMuted)),
                      const SizedBox(height: 20),
                    ]),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Analytics.billProceedCheckout(
                            itemCount: _billItems.length);
                        setState(() => _view = BillingView.settlement);
                      },
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('बिल सेटल करें →',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ] else ...[
                  // ── Issue list ────────────────────────────────────────────────
                  Row(children: [
                    const Text('⚠️', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    const Text('स्टॉक कम है',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.warning)),
                  ]),
                  const SizedBox(height: 4),
                  const Text('इन आइटम का स्टॉक मांगी मात्रा से कम है:',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  const SizedBox(height: 12),

                  ...live.map((e) {
                    final idx = e.key;
                    final item = e.value;
                    final available = item.currentStock.toInt();
                    final requested = item.quantity.toInt();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warningLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(item.itemName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14)),
                              ),
                              Text(
                                available <= 0
                                    ? 'स्टॉक खत्म'
                                    : 'मांगे: $requested  •  बचे: $available',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.warning,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(children: [
                            if (available > 0) ...[
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    _updateItem(idx, qty: item.currentStock);
                                    setModal(() {});
                                    setState(() {});
                                  },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.warning,
                                    side: BorderSide(
                                        color: AppColors.warning
                                            .withValues(alpha: 0.5)),
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: Text('$available रखें',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  _removeItem(idx);
                                  setModal(() {});
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.danger,
                                  side:
                                      const BorderSide(color: AppColors.danger),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('हटाएं',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    );
                  }),

                  const SizedBox(height: 4),
                  const Divider(),
                  const SizedBox(height: 8),

                  // Footer: back-to-fix + soft override
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('बिल ठीक करें',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          // Soft override — shopkeeper may know stock is physically
                          // available but not yet updated in the app.
                          Navigator.pop(ctx);
                          Analytics.billProceedCheckout(
                              itemCount: _billItems.length);
                          setState(() => _view = BillingView.settlement);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('फिर भी जारी रखें',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ),
                    ),
                  ]),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // ── VIEW 2: SETTLEMENT ──────────────────────────────────────────────────────

  Widget _buildSettlement() {
    final suggestions = _customerNames
        .where((n) =>
            n.toLowerCase().contains(_customerController.text.toLowerCase()))
        .toList();

    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            decoration: BoxDecoration(
              gradient: primaryGradient,
              borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(children: [
                  Row(children: [
                    IconButton(
                      onPressed: () =>
                          setState(() => _view = BillingView.input),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('बिल सेटलमेंट',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16)),
                          Text('भुगतान की जानकारी भरें',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                        ]),
                  ]),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Column(children: [
                      const Text('कुल राशि',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('₹${_grandTotal.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1)),
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
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textMuted,
                                letterSpacing: 0.6)),
                      ),
                    ),
                    // Only show valid (non-error) items — matches _finalizeBill filter.
                    ..._billItems
                        .where((i) => i.itemName.isNotEmpty && !i.hasError)
                        .map((item) => Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 6),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                      child: RichText(
                                    text: TextSpan(
                                      style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 13),
                                      children: [
                                        TextSpan(
                                            text: item.itemName,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w500)),
                                        TextSpan(
                                            text: ' × ${item.quantity}',
                                            style: const TextStyle(
                                                color: AppColors.textMuted)),
                                      ],
                                    ),
                                  )),
                                  Text('₹${item.itemTotal.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13)),
                                ],
                              ),
                            )),
                    if (_discount > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('छूट',
                                style: TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w600)),
                            Text('-₹${_discount.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w700)),
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
                        const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('उधार पर?',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14)),
                              Text('ग्राहक अभी भुगतान नहीं करेगा',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted)),
                            ]),
                        Switch(
                          value: _isCredit,
                          onChanged: (v) => setState(() {
                            _isCredit = v;
                            if (!v) {
                              _isSplit = false;
                              _nagadCtrl.clear();
                            }
                          }),
                          activeThumbColor: AppColors.primary,
                        ),
                      ],
                    ),

                    // Split toggle — only visible when credit is on
                    if (_isCredit) ...[
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('कुछ नकद भी दिया?',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13)),
                                Text('Part cash + part credit',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textMuted)),
                              ]),
                          Switch(
                            value: _isSplit,
                            onChanged: (v) => setState(() {
                              _isSplit = v;
                              if (!v) _nagadCtrl.clear();
                            }),
                            activeColor: AppColors.warning,
                          ),
                        ],
                      ),
                      if (_isSplit) ...[
                        const SizedBox(height: 10),
                        Builder(builder: (ctx) {
                          final subTotal =
                              _billItems.fold(0.0, (s, i) => s + i.itemTotal);
                          final finalTotal = (subTotal - _discount)
                              .clamp(0.0, double.infinity);
                          final nagadAmt =
                              double.tryParse(_nagadCtrl.text) ?? 0;
                          final udharAmt = (finalTotal - nagadAmt)
                              .clamp(0.0, double.infinity);
                          return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('अभी नकद दिया (₹)',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textMuted)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _nagadCtrl,
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    prefixText: '₹ ',
                                    hintText: '0',
                                    isDense: true,
                                    suffixText:
                                        'max ₹${finalTotal.toStringAsFixed(0)}',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppColors.warningLight,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: AppColors.warning
                                            .withValues(alpha: 0.35)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('बकाया रहेगा:',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.warning,
                                              fontWeight: FontWeight.w600)),
                                      Text('₹${udharAmt.toStringAsFixed(0)}',
                                          style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.warning)),
                                    ],
                                  ),
                                ),
                              ]);
                        }),
                      ],
                    ],

                    const Divider(height: 24),

                    // Customer name
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ग्राहक का नाम',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textMuted,
                                letterSpacing: 0.4)),
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
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textMuted),
                                    ),
                                  )
                                : ListView(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    children: suggestions
                                        .map((name) => ListTile(
                                              dense: true,
                                              title: Text(name,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 13)),
                                              onTap: () {
                                                _customerController.text = name;
                                                setState(() {
                                                  _customerName = name;
                                                  _showCustomerSuggestions =
                                                      false;
                                                });
                                                _customerFocusNode.unfocus();
                                              },
                                            ))
                                        .toList(),
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
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : const Icon(Icons.check_circle_outline),
                    label: Text(
                        _isProcessing
                            ? 'प्रोसेस हो रहा है...'
                            : 'बिल पक्का करें',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
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
                colors: [
                  AppColors.successGradientDark,
                  AppColors.successGradientMid
                ],
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
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.2),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4), width: 2),
                    ),
                    child: const Icon(Icons.check_circle_outline,
                        color: Colors.white, size: 38),
                  ),
                  const SizedBox(height: 16),
                  const Text('बिल पक्का हो गया!',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 22)),
                  const SizedBox(height: 4),
                  const Text('बिल सफलतापूर्वक सहेजा गया',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Column(children: [
                      const Text('कुल राशि',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                      Text('₹${_finalTotal.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1)),
                      if (_customerName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${_isCredit ? "🔴 उधार" : "🟢 नकद"} — $_customerName',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13),
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
                // PDF actions — side by side
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _downloadPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('PDF',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side: const BorderSide(color: AppColors.borderStrong),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _sharePdfOnWhatsApp,
                      icon: const Icon(Icons.share_outlined, size: 18),
                      label: const Text('शेयर करें',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        foregroundColor: AppColors.whatsappGreen,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side: const BorderSide(color: AppColors.whatsappGreen),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _sharePdfOnWhatsApp,
                    icon: const Icon(Icons.share_outlined,
                        color: Color(0xFF25D366)),
                    label: const Text('WhatsApp पर शेयर करें',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: Color(0xFF25D366))),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
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
                    label: const Text('नया बिल बनाएं',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
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
