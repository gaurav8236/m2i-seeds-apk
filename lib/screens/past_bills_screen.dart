import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import '../utils/bill_pdf.dart';

class PastBillsScreen extends StatefulWidget {
  const PastBillsScreen({super.key});

  @override
  State<PastBillsScreen> createState() => _PastBillsScreenState();
}

class _PastBillsScreenState extends State<PastBillsScreen> {
  List<Bill> _bills = [];
  bool _loading = true;
  String _search = '';
  String _filter = 'All'; // All, Cash, Credit

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final bills = await SupabaseService.fetchPastBills();
      setState(() => _bills = bills);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('लोड नहीं हो सका: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  List<Bill> get _filtered {
    return _bills.where((b) {
      final q = _search.toLowerCase();
      final nameMatch = (b.customerName ?? '').toLowerCase().contains(q) || q.isEmpty;
      final typeMatch = _filter == 'All' ||
          (_filter == 'Cash' && !b.isCredit) ||
          (_filter == 'Credit' && b.isCredit);
      return nameMatch && typeMatch;
    }).toList();
  }

  String _fmt(double n) =>
      n >= 1000 ? '₹${(n / 1000).toStringAsFixed(1)}k' : '₹${n.toStringAsFixed(0)}';

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
                bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Column(children: [
                  Row(children: [
                    if (Navigator.canPop(context))
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    if (Navigator.canPop(context)) const SizedBox(width: 10),
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.history, color: Colors.white, size: 17),
                    ),
                    const SizedBox(width: 8),
                    const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('पुराने बिल', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                      Text('बिल इतिहास', style: TextStyle(color: Colors.white70, fontSize: 10)),
                    ]),
                  ]),
                ]),
              ),
            ),
          ),

          // Search + filter
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Column(children: [
              TextField(
                decoration: const InputDecoration(
                  hintText: 'ग्राहक का नाम खोजें...',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 8),
              Row(children: [
                ...[
                  ('All', 'सभी'),
                  ('Cash', 'नकद'),
                  ('Credit', 'उधार'),
                ].map((item) => GestureDetector(
                  onTap: () => setState(() => _filter = item.$1),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: _filter == item.$1 ? AppColors.primary : AppColors.surface2,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _filter == item.$1 ? AppColors.primary : AppColors.border),
                    ),
                    child: Text(item.$2, style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: _filter == item.$1 ? Colors.white : AppColors.textSecondary,
                    )),
                  ),
                )),
              ]),
            ]),
          ),

          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _filtered.isEmpty
                        ? const Center(
                            child: Text('कोई बिल नहीं', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => _billCard(_filtered[i]),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _billCard(Bill bill) {
    return GestureDetector(
      onTap: () => _showDetail(bill),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bill.isCredit ? AppColors.dangerLight : AppColors.successLight,
            ),
            child: Icon(
              bill.isCredit ? Icons.credit_card_outlined : Icons.payments_outlined,
              size: 20,
              color: bill.isCredit ? AppColors.danger : AppColors.success,
            ),
          ),
          title: Text(
            bill.customerName ?? 'नकद ग्राहक',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          subtitle: Text(
            '${DateFormat('dd MMM yyyy, hh:mm a').format(bill.createdAt)} · ${bill.billDetails.length} आइटम',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_fmt(bill.totalAmount),
                      style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16,
                        color: bill.isCredit ? AppColors.danger : AppColors.success,
                      )),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: bill.isCredit ? AppColors.dangerLight : AppColors.successLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      bill.isCredit ? 'उधार' : 'नकद',
                      style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        color: bill.isCredit ? AppColors.danger : AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(Bill bill) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BillDetailSheet(bill: bill),
    );
  }
}

// ── Bill Detail Sheet ────────────────────────────────────────────────────────

class _BillDetailSheet extends StatelessWidget {
  final Bill bill;
  const _BillDetailSheet({required this.bill});

  String _fmt(double n) =>
      n >= 1000 ? '₹${(n / 1000).toStringAsFixed(1)}k' : '₹${n.toStringAsFixed(0)}';

  Future<void> _printPdf(BuildContext context) async {
    final items = bill.billDetails.map((d) => BillItem.fromMap(d)).toList();
    final discount = bill.discountAmount ?? 0;
    final subTotal = bill.totalAmount + discount;
    final bytes = await buildBillPdfBytes(
      items: items,
      customerName: bill.customerName ?? '',
      isCredit: bill.isCredit,
      subTotal: subTotal,
      discount: discount,
      grandTotal: bill.totalAmount,
      date: bill.createdAt,
    );
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _sharePdfOnWhatsApp() async {
    final items = bill.billDetails.map((d) => BillItem.fromMap(d)).toList();
    final discount = bill.discountAmount ?? 0;
    final subTotal = bill.totalAmount + discount;
    final bytes = await buildBillPdfBytes(
      items: items,
      customerName: bill.customerName ?? '',
      isCredit: bill.isCredit,
      subTotal: subTotal,
      discount: discount,
      grandTotal: bill.totalAmount,
      date: bill.createdAt,
    );
    await Printing.sharePdf(bytes: bytes, filename: 'bill.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: DraggableScrollableSheet(
        expand: false,
        maxChildSize: 0.92,
        initialChildSize: 0.65,
        builder: (_, ctrl) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(bill.customerName ?? 'नकद ग्राहक',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                    Text(DateFormat('dd MMM yyyy, hh:mm a').format(bill.createdAt),
                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ]),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: bill.isCredit ? AppColors.dangerLight : AppColors.successLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(bill.isCredit ? 'उधार' : 'नकद',
                        style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: bill.isCredit ? AppColors.danger : AppColors.success,
                        )),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),

            Expanded(
              child: ListView(
                controller: ctrl,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  const SizedBox(height: 12),

                  // Items header
                  const Row(
                    children: [
                      Expanded(flex: 3, child: Text('आइटम', style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w700))),
                      Expanded(flex: 1, child: Text('इकाई', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w700))),
                      Expanded(flex: 2, child: Text('दर', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w700))),
                      Expanded(flex: 1, child: Text('मात्रा', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w700))),
                      Expanded(flex: 2, child: Text('कुल', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w700))),
                    ],
                  ),
                  const Divider(),

                  ...bill.billDetails.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(flex: 3, child: Text(item['item_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                        Expanded(flex: 1, child: Text(item['unit'] ?? '-', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
                        Expanded(flex: 2, child: Text('₹${item['price_per_unit'] ?? 0}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                        Expanded(flex: 1, child: Text('${item['quantity_billed'] ?? 0}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                        Expanded(flex: 2, child: Text('₹${item['item_total'] ?? 0}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primary))),
                      ],
                    ),
                  )),

                  const Divider(),

                  // Totals
                  if ((bill.discountAmount ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('छूट', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
                          Text('-₹${bill.discountAmount!.toStringAsFixed(0)}',
                              style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('कुल राशि', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        Text('₹${bill.totalAmount.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.primary, letterSpacing: -0.5)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _printPdf(context),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('PDF डाउनलोड / प्रिंट', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: const BorderSide(color: AppColors.borderStrong),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _sharePdfOnWhatsApp,
                      icon: const Icon(Icons.share_outlined, size: 18, color: Color(0xFF25D366)),
                      label: const Text('WhatsApp पर शेयर करें',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF25D366))),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: const BorderSide(color: Color(0xFF25D366)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
