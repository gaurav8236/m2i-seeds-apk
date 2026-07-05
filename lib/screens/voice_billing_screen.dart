import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import 'past_bills_screen.dart';

enum BillingView { input, settlement, success }

class VoiceBillingScreen extends StatefulWidget {
  const VoiceBillingScreen({super.key});

  @override
  State<VoiceBillingScreen> createState() => _VoiceBillingScreenState();
}

class _VoiceBillingScreenState extends State<VoiceBillingScreen>
    with TickerProviderStateMixin {
  BillingView _view = BillingView.input;
  bool _isRecording = false;
  bool _isProcessing = false;
  String _spokenText = '';
  List<BillItem> _billItems = [];
  List<StockItem> _stockList = [];
  List<String> _customerNames = [];
  double _discount = 0;
  bool _isCredit = false;
  String _customerName = '';
  double _finalTotal = 0;

  // Settlement
  final _customerController = TextEditingController();
  bool _showCustomerSuggestions = false;

  // Waveform animation
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _loadData();
  }

  @override
  void dispose() {
    _waveController.dispose();
    _customerController.dispose();
    VoiceService.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final stock = await SupabaseService.fetchStock();
    final names = await SupabaseService.fetchCustomerNames();
    setState(() {
      _stockList = stock;
      _customerNames = names;
    });
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
    return stock.unit.isEmpty ? 'unit' : stock.unit;
  }

  Future<void> _startRecording() async {
    var status = await Permission.microphone.status;

    if (!status.isGranted) {
      status = await Permission.microphone.request();
      if (!status.isGranted) {
        if (mounted) _showSnack('माइक की अनुमति चाहिए');
        return;
      }
      // Permission just granted — Android hasn't propagated it to the audio
      // subsystem yet. Return and let the user tap once more to start recording.
      if (mounted) _showSnack('अनुमति मिल गई! अब माइक दबाएं');
      return;
    }

    try {
      await VoiceService.startRecording();
      setState(() {
        _isRecording = true;
        _spokenText = '';
        _billItems = [];
      });
    } catch (e) {
      if (mounted) _showSnack('रिकॉर्डिंग शुरू नहीं हो सकी: $e');
    }
  }

  Future<void> _stopRecording() async {
    setState(() => _isRecording = false);
    final path = await VoiceService.stopRecording();
    if (path == null) return;

    setState(() => _isProcessing = true);
    try {
      final results = await VoiceService.processVoice(audioPath: path);
      final processed = _processResults(results);
      setState(() => _billItems = processed);
    } catch (e) {
      _showSnack('आवाज़ प्रोसेस नहीं हो सकी: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  List<BillItem> _processResults(List<Map<String, dynamic>> results) {
    final processed = <BillItem>[];
    for (final r in results) {
      final hasError = r['error'] != null && r['error'] != false;

      if (!hasError) {
        processed.add(BillItem.fromMap(r));
      } else if (r['error'] is String) {
        // Try to extract closest match
        final errorStr = r['error'] as String;
        final match = RegExp(r'Closest:\s*(.+?)\s*\(\d+%\)').firstMatch(errorStr);
        if (match != null) {
          final closestName = match.group(1)!.trim();
          final stockItem = _stockList.firstWhere(
            (s) => s.itemName == closestName,
            orElse: () => StockItem(
                id: '', currentStock: 0, sellingPrice: 0, lowStockLimit: 0,
                aliases: [], itemName: '', category: '', unit: ''),
          );
          if (stockItem.id.isNotEmpty) {
            final qty = (r['quantity_billed'] as num?)?.toDouble() ?? 1;
            final price = stockItem.sellingPrice;
            processed.add(BillItem(
              itemName: closestName,
              quantity: qty,
              pricePerUnit: price,
              itemTotal: qty * price,
              stockRemaining: stockItem.currentStock - qty,
              stockId: stockItem.id,
              currentStock: stockItem.currentStock,
              unit: stockItem.unit,
            ));
          }
        }
        // else skip — no match
      }
      // error == true → skip
    }
    return processed;
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

      setState(() {
        _finalTotal = finalTotal;
        _view = BillingView.success;
      });
      await _loadData();
    } catch (e) {
      _showSnack('बिल सहेजने में त्रुटि: $e');
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _downloadPdf() async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(child: pw.Text('SmartDukan',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18))),
          pw.Center(child: pw.Text('दुकानदार सहायक', style: const pw.TextStyle(fontSize: 11))),
          pw.SizedBox(height: 10),
          pw.Divider(),
          pw.Text('Date: ${DateTime.now().toString().split('.').first}'),
          if (_customerName.isNotEmpty) pw.Text('Customer: $_customerName'),
          pw.Divider(),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            children: [
              pw.TableRow(children: [
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Item', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Unit', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Rate', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Qty', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
              ]),
              ..._billItems.map((item) => pw.TableRow(children: [
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(item.itemName)),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(_getUnit(item))),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('₹${item.pricePerUnit}')),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('${item.quantity}')),
                pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('₹${item.itemTotal}')),
              ])),
            ],
          ),
          pw.SizedBox(height: 8),
          if (_discount > 0) pw.Text('Discount: -₹${_discount.toStringAsFixed(2)}'),
          pw.Text('Total: ₹${_finalTotal.toStringAsFixed(2)}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
          pw.SizedBox(height: 16),
          pw.Center(child: pw.Text('धन्यवाद! फिर पधारें।')),
        ],
      ),
    ));
    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  void _resetBill() {
    setState(() {
      _view = BillingView.input;
      _billItems = [];
      _spokenText = '';
      _discount = 0;
      _isCredit = false;
      _customerName = '';
      _customerController.clear();
      _finalTotal = 0;
    });
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
              boxShadow: [BoxShadow(color: const Color(0xFF0D47A1).withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 4))],
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
                            border: Border.all(color: Colors.white.withOpacity(0.3)),
                          ),
                          child: const Icon(Icons.mic, color: Colors.white, size: 17),
                        ),
                        const SizedBox(width: 8),
                        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('SmartDukan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                          Text('Voice Billing', style: TextStyle(color: Colors.white70, fontSize: 10)),
                        ]),
                      ]),
                      TextButton.icon(
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const PastBillsScreen())),
                        icon: const Icon(Icons.history, color: Colors.white, size: 14),
                        label: const Text('इतिहास', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(color: Colors.white.withOpacity(0.3)),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('कुल राशि',
                            style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12, fontWeight: FontWeight.w600)),
                        Text('₹${_grandTotal.toStringAsFixed(0)}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: -0.5)),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                // Mic Zone
                _micZone(),
                const SizedBox(height: 16),
                // Bill table
                if (_billItems.isNotEmpty) _billTable(),
                const SizedBox(height: 80),
              ]),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomSheet: (_billItems.isNotEmpty)
          ? _settleBar()
          : null,
    );
  }

  Widget _micZone() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        children: [
          // Mic button
          GestureDetector(
            onTap: _isProcessing ? null : (_isRecording ? _stopRecording : _startRecording),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 88, height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: _isRecording
                    ? const LinearGradient(
                        colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: (_isRecording ? AppColors.danger : AppColors.primary).withOpacity(0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: _isProcessing
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                    )
                  : const Icon(Icons.mic, color: Colors.white, size: 34),
            ),
          ),
          const SizedBox(height: 16),

          // Waveform
          if (_isRecording)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(8, (i) => _waveBar(i)),
            ),

          const SizedBox(height: 8),

          // Status text
          if (_isProcessing)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary)),
                SizedBox(width: 8),
                Text('AI आइटम पहचान रहा है...', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 14)),
              ],
            )
          else if (_isRecording)
            Column(children: [
              const Text('सुन रहा है... बोलते रहें',
                  style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 6),
              OutlinedButton(
                onPressed: _stopRecording,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                ),
                child: const Text('रोकें — Stop', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ])
          else
            Column(children: const [
              Text('माइक दबाएं और बोलें',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
              SizedBox(height: 4),
              Text('हिंदी या English — "aloo do kilo, maggi ek"',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ]),

          // Transcript
          if (_spokenText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.successLight,
                border: Border.all(color: const Color(0xFFBBF7D0)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('AI ने सुना',
                    style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                const SizedBox(height: 4),
                Text('"$_spokenText"',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF14532D), fontStyle: FontStyle.italic)),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _waveBar(int i) {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (_, __) {
        final height = 8 + (24 * (0.5 + 0.5 * (_waveController.value + i * 0.12).clamp(0, 1)));
        return Container(
          width: 3,
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: AppColors.danger,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      },
    );
  }

  Widget _billTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
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
                Text('${_billItems.length} item${_billItems.length != 1 ? "s" : ""}',
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
                Expanded(flex: 1, child: Text('इकाई', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
                Expanded(flex: 2, child: Text('कुल (₹)', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          // Items
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
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
    return Container(
      color: item.hasError ? AppColors.dangerLight : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Item name
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _showItemPicker(i),
                  child: Text(
                    item.itemName.isEmpty ? 'आइटम का नाम' : item.itemName,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: item.itemName.isEmpty ? AppColors.textMuted : AppColors.textPrimary,
                    ),
                  ),
                ),
                if (item.itemName.isNotEmpty)
                  Text('₹/${_getUnit(item)}',
                      style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
              ],
            ),
          ),

          // Price stepper
          Expanded(
            flex: 2,
            child: _stepper(item.pricePerUnit, (v) => _updateItem(i, price: v)),
          ),

          // Quantity stepper
          Expanded(
            flex: 2,
            child: _stepper(item.quantity, (v) => _updateItem(i, qty: v)),
          ),

          // Unit badge
          Expanded(
            flex: 1,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  _getUnit(item),
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
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
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 13)),
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

  Widget _stepper(double value, ValueChanged<double> onChange) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _stepBtn('-', () => onChange((value - 1).clamp(0, double.infinity))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        ),
        _stepBtn('+', () => onChange(value + 1)),
      ],
    );
  }

  Widget _stepBtn(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 22, height: 22,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
        ),
      );

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
    );
  }

  Widget _discountSection() {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('छूट (Discount)',
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
                        backgroundColor: Colors.white.withOpacity(0.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('बिल सेटलमेंट', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                      Text('Settlement', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ]),
                  ]),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
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
                          Text('On Credit', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        ]),
                        Switch(
                          value: _isCredit,
                          onChanged: (v) => setState(() => _isCredit = v),
                          activeColor: AppColors.primary,
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
                          decoration: const InputDecoration(
                            hintText: 'खोजें या नया नाम लिखें...',
                          ),
                          onChanged: (v) {
                            setState(() {
                              _customerName = v;
                              _showCustomerSuggestions = v.isNotEmpty;
                            });
                          },
                        ),
                        if (_showCustomerSuggestions && suggestions.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: suggestions.take(5).map((name) => ListTile(
                                dense: true,
                                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                onTap: () {
                                  _customerController.text = name;
                                  setState(() {
                                    _customerName = name;
                                    _showCustomerSuggestions = false;
                                  });
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
                      color: Colors.white.withOpacity(0.2),
                      border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
                    ),
                    child: const Icon(Icons.check_circle_outline, color: Colors.white, size: 38),
                  ),
                  const SizedBox(height: 16),
                  const Text('बिल पक्का हो गया!',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22)),
                  const SizedBox(height: 4),
                  const Text('Bill saved successfully',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Column(children: [
                      const Text('कुल राशि', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                      Text('₹${_finalTotal.toStringAsFixed(0)}',
                          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -1)),
                      if (_customerName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${_isCredit ? "🔴 उधार" : "🟢 नकद"} — $_customerName',
                          style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
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
