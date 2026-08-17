import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../models/models.dart';
import '../theme.dart';
import '../services/auth_service.dart';
import '../utils/bill_pdf.dart';

// ── Shared filter type ───────────────────────────────────────────────────────

enum BillTypeFilter { all, cash, credit }

extension BillTypeFilterLabel on BillTypeFilter {
  String get label {
    switch (this) {
      case BillTypeFilter.all:    return 'सभी';
      case BillTypeFilter.cash:   return 'नकद';
      case BillTypeFilter.credit: return 'उधार';
    }
  }

  bool matches(Bill bill) {
    switch (this) {
      case BillTypeFilter.all:    return true;
      case BillTypeFilter.cash:   return !bill.isCredit;
      case BillTypeFilter.credit: return bill.isCredit;
    }
  }
}

// ── Filter chips row ─────────────────────────────────────────────────────────

class BillFilterChips extends StatelessWidget {
  final BillTypeFilter selected;
  final ValueChanged<BillTypeFilter> onChanged;

  const BillFilterChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: BillTypeFilter.values.map((f) {
        final active = f == selected;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => onChanged(f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: active ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Text(
                f.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Bill card ────────────────────────────────────────────────────────────────

class BillCard extends StatelessWidget {
  final Bill bill;
  final EdgeInsetsGeometry margin;

  const BillCard({
    super.key,
    required this.bill,
    this.margin = const EdgeInsets.only(bottom: 8),
  });

  String _fmt(double n) =>
      n >= 1000 ? '₹${(n / 1000).toStringAsFixed(1)}k' : '₹${n.toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    final isCredit = bill.isCredit;
    final color = isCredit ? AppColors.danger : AppColors.success;
    final bgColor = isCredit ? AppColors.dangerLight : AppColors.successLight;
    final icon = isCredit ? Icons.credit_card_outlined : Icons.payments_outlined;

    return GestureDetector(
      onTap: () => showBillDetail(context, bill),
      child: Container(
        margin: margin,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  bill.customerName ?? 'नकद ग्राहक',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${DateFormat('dd MMM, hh:mm a').format(bill.createdAt)} · ${bill.billDetails.length} आइटम',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                _fmt(bill.totalAmount),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color),
              ),
              Container(
                margin: const EdgeInsets.only(top: 3),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isCredit ? 'उधार' : 'नकद',
                  style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700, color: color,
                  ),
                ),
              ),
            ]),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
          ]),
        ),
      ),
    );
  }
}

// ── Show bill detail (shared entry point) ────────────────────────────────────

void showBillDetail(BuildContext context, Bill bill) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _BillDetailSheet(bill: bill),
  );
}

// ── Bill detail bottom sheet ─────────────────────────────────────────────────

class _BillDetailSheet extends StatefulWidget {
  final Bill bill;
  const _BillDetailSheet({required this.bill});

  @override
  State<_BillDetailSheet> createState() => _BillDetailSheetState();
}

class _BillDetailSheetState extends State<_BillDetailSheet> {
  bool _printLoading = false;
  bool _shareLoading = false;

  String _fmt(double n) =>
      n >= 1000 ? '₹${(n / 1000).toStringAsFixed(1)}k' : '₹${n.toStringAsFixed(0)}';

  Future<void> _buildAndShare({required bool isPrint}) async {
    setState(() => isPrint ? _printLoading = true : _shareLoading = true);
    try {
      final bill = widget.bill;
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
        // Use cached shop name so reprints show the correct dukan name (#8).
        shopName: AuthService.shopName,
      );
      if (isPrint) {
        await Printing.layoutPdf(onLayout: (_) async => bytes);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: 'bill.pdf');
      }
    } finally {
      if (mounted) setState(() => isPrint ? _printLoading = false : _shareLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    final isCredit = bill.isCredit;
    final color = isCredit ? AppColors.danger : AppColors.success;
    final bgColor = isCredit ? AppColors.dangerLight : AppColors.successLight;
    final icon = isCredit ? Icons.credit_card_outlined : Icons.payments_outlined;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    bill.customerName ?? 'नकद ग्राहक',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary),
                  ),
                  Text(
                    DateFormat('dd MMM yyyy, hh:mm a').format(bill.createdAt),
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  isCredit ? 'उधार' : 'नकद',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ]),
          ),

          const Divider(height: 1, color: AppColors.border),

          // Items list
          Expanded(
            child: ListView(
              controller: ctrl,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              children: [
                const Text(
                  'आइटम',
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppColors.textMuted, letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                ...bill.billDetails.map((item) {
                  final name  = item['item_name']?.toString() ?? '';
                  final qty   = (item['quantity_billed'] as num?)?.toDouble() ?? 0;
                  final price = (item['price_per_unit'] as num?)?.toDouble() ?? 0;
                  final total = (item['item_total'] as num?)?.toDouble() ?? 0;
                  final unit  = item['unit']?.toString() ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name, style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13,
                            color: AppColors.textPrimary,
                          )),
                          Text(
                            '${qty % 1 == 0 ? qty.toInt() : qty.toStringAsFixed(1)} $unit × ₹${price.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                          ),
                        ]),
                      ),
                      Text(
                        '₹${total.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ]),
                  );
                }),

                const Divider(color: AppColors.border),

                // Discount
                if ((bill.discountAmount ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('छूट', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                        Text(
                          '- ₹${bill.discountAmount!.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 13, color: AppColors.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Total
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('कुल', style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15,
                      color: AppColors.textPrimary,
                    )),
                    Text(_fmt(bill.totalAmount), style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 18,
                      color: color, letterSpacing: -0.5,
                    )),
                  ],
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),

          // Action buttons
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (_printLoading || _shareLoading) ? null : () => _buildAndShare(isPrint: true),
                  icon: _printLoading
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                      : const Icon(Icons.picture_as_pdf_outlined, size: 16),
                  label: const Text('PDF / प्रिंट'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_printLoading || _shareLoading) ? null : () => _buildAndShare(isPrint: false),
                  icon: _shareLoading
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.share_outlined, size: 16),
                  label: const Text('WhatsApp'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
