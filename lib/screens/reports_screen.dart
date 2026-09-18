import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import '../widgets/bill_card.dart';

// BUG-13: transaction types that are debt collection / advance / loan money,
// not sales revenue — must not contribute to the "नकद बिक्री" / "उधार बिक्री"
// / "कुल बिक्री" summary cards on the Reports screen. Mirrors the exclusion
// list SupabaseService.fetchFilteredStats() already applies at the query
// level. Deliberately does NOT change how a `split` bill is classified here
// (still whole-amount into उधार बिक्री) — that half is an open
// product-policy question (`.claude/TODOS.md`), not part of this fix.
//
// NOTE (credit-ledger removal): 'payment'/'deposit' rows are historical only
// — the UI that created them (the customer-ledger settlement dialog) has
// been removed, but old rows of these types may still exist in past_bills
// and must keep being excluded from the sales totals below.
const _nonSaleTransactionTypes = {'payment', 'deposit', 'cash_loan'};

// Pure summary result for the Reports screen's 3 sales-summary cards.
// Extracted out of `_ReportsScreenState._reportsTab()` (BUG-13) so it can be
// unit-tested without a live Supabase call/mock — mirrors the seam
// SupabaseService.bucketFilteredStats() added for BUG-12.
@visibleForTesting
class ReportsSalesSummary {
  final double cashTotal;
  final double creditTotal;
  final int cashCount;
  final int creditCount;
  final int salesCount;
  const ReportsSalesSummary({
    required this.cashTotal,
    required this.creditTotal,
    required this.cashCount,
    required this.creditCount,
    required this.salesCount,
  });
}

// Partitions `bills` (already period/type-filtered by the caller) into
// cash/credit sales totals, excluding payment/deposit/cash_loan rows from
// all three summary numbers (BUG-13) — the bill list rendered below the
// cards is untouched by this function; it keeps showing every filtered bill.
@visibleForTesting
ReportsSalesSummary computeReportsSalesSummary(List<Bill> bills) {
  final salesBills = bills
      .where((b) => !_nonSaleTransactionTypes.contains(b.transactionType))
      .toList();
  final creditBills = salesBills.where((b) => b.isCredit).toList();
  final cashBills = salesBills.where((b) => !b.isCredit).toList();
  return ReportsSalesSummary(
    cashTotal: cashBills.fold(0.0, (s, b) => s + b.totalAmount),
    creditTotal: creditBills.fold(0.0, (s, b) => s + b.totalAmount),
    cashCount: cashBills.length,
    creditCount: creditBills.length,
    salesCount: salesBills.length,
  );
}

// ── Reports screen ───────────────────────────────────────────────────────────
//
// Sales reporting only — period filters + नकद/उधार/कुल summary cards + bill
// history. The customer-ledger tab (customer list, outstanding balances,
// opening balance, payment/deposit settlement) that used to live alongside
// this has been removed entirely; every bill still records is_credit /
// transaction_type at checkout time (voice_billing_screen.dart), this screen
// just no longer offers any way to track or settle a running balance from it.
class ReportsScreen extends StatefulWidget {
  final void Function(VoidCallback) onRegisterReload;
  const ReportsScreen({super.key, required this.onRegisterReload});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _loading = true;

  // Stats + filter
  StatsPeriod _period = StatsPeriod.thisMonth;
  DateTimeRange? _customRange;
  double _credit = 0, _paid = 0;
  BillTypeFilter _typeFilter = BillTypeFilter.all;

  // Reports
  List<Bill> _allBills = [];

  @override
  void initState() {
    super.initState();
    widget.onRegisterReload(_load);
    _load();
  }

  DateTimeRange _rangeFor(StatsPeriod p) {
    final now = DateTime.now();
    switch (p) {
      // Use exclusive-midnight upper bounds for all periods — same pattern as the
      // custom range fix (Sprint 6). DateTime handles day/month overflow correctly
      // (e.g. day 32 → next month, month 13 → next year).  fetchFilteredStats
      // converts these local (IST) DateTimes to UTC before the Supabase query. (#47)
      case StatsPeriod.today:
        return DateTimeRange(
            start: DateTime(now.year, now.month, now.day),
            end: DateTime(now.year, now.month, now.day + 1));
      case StatsPeriod.thisWeek:
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return DateTimeRange(
            start: DateTime(monday.year, monday.month, monday.day),
            end: DateTime(now.year, now.month, now.day + 1));
      case StatsPeriod.thisMonth:
        return DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: DateTime(now.year, now.month + 1, 1));
      case StatsPeriod.custom:
        final cr = _customRange;
        if (cr == null) {
          // Null fallback uses thisMonth bounds — consistent exclusive midnight (#47)
          return DateTimeRange(
              start: DateTime(now.year, now.month, 1),
              end: DateTime(now.year, now.month + 1, 1));
        }
        // The date picker returns `end` as midnight of the chosen day (exclusive
        // start of that day). We need to include the full chosen end-day, so
        // advance to midnight of the NEXT day — the exclusive upper bound.
        //
        // _filteredBills adds Duration(days:1) to range.end before comparing, so
        // using 23:59:59 here would cause it to include one extra day.  Midnight-
        // of-next-day is the correct value: server query gets all IST bills up to
        // 23:59:59 on the end-day; client filter gets midnight+1-day which is a
        // harmless ceiling since no future bills exist (#16).
        //
        // DateTime handles day overflow correctly (e.g. day 32 → next month).
        return DateTimeRange(
          start: cr.start,
          end: DateTime(cr.end.year, cr.end.month, cr.end.day + 1),
        );
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final range = _rangeFor(_period);
      final results = await Future.wait([
        SupabaseService.fetchFilteredStats(from: range.start, to: range.end),
        SupabaseService.fetchPastBills(),
      ]);
      final stats = results[0] as Map<String, double>;
      final bills = results[1] as List<Bill>;
      setState(() {
        _credit = stats['credit'] ?? 0;
        _paid = stats['paid'] ?? 0;
        _allBills = bills;
      });
    } catch (e) {
      _showSnack('लोड नहीं हो सका: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      _customRange = picked;
      setState(() => _period = StatsPeriod.custom);
      _load();
    }
  }

  List<Bill> get _filteredBills {
    final range = _rangeFor(_period);
    return _allBills
        .where((b) =>
            b.createdAt.isAfter(range.start) &&
            b.createdAt.isBefore(range.end.add(const Duration(days: 1))) &&
            _typeFilter.matches(b))
        .toList();
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // Bug #55: ₹3,090 was showing as ₹3.0k — threshold was too low.
  // Now: below ₹1L shows full Indian-comma format (₹3,090 / ₹13,184);
  // ₹1L+ shows compact (₹1.5L).
  String _fmt(double n) {
    if (n >= 100000) return '₹${(n / 100000).toStringAsFixed(1)}L';
    return '₹${NumberFormat('#,##,##0', 'en_IN').format(n.round())}';
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(children: [
                Row(children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.receipt_long_outlined,
                        color: Colors.white, size: 17),
                  ),
                  const SizedBox(width: 8),
                  const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('रिपोर्ट',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                        Text('बिक्री रिपोर्ट और बिल इतिहास',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 10)),
                      ]),
                ]),
                const SizedBox(height: 12),

                // Period filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _periodChip('आज', StatsPeriod.today),
                    const SizedBox(width: 8),
                    _periodChip('यह हफ़्ता', StatsPeriod.thisWeek),
                    const SizedBox(width: 8),
                    _periodChip('यह महीना', StatsPeriod.thisMonth),
                    const SizedBox(width: 8),
                    _customChip(),
                  ]),
                ),
                const SizedBox(height: 12),

                // Stats — period-filtered नकद जमा / उधार दिया only (no
                // all-time outstanding/balance figure — see file header note).
                Row(children: [
                  Expanded(child: _headerStat('उधार दिया', _fmt(_credit))),
                  _vDivider(),
                  Expanded(child: _headerStat('नकद जमा', _fmt(_paid))),
                ]),
              ]),
            ),
          ),
        ),

        Expanded(child: _reportsBody()),
      ]),
    );
  }

  // ── FILTER CHIPS ────────────────────────────────────────────────────────────

  Widget _periodChip(String label, StatsPeriod period) {
    final active = _period == period;
    return GestureDetector(
      onTap: () {
        if (_period == period) return;
        setState(() => _period = period);
        _load();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: Colors.white.withValues(alpha: active ? 0 : 0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.primary : Colors.white)),
      ),
    );
  }

  Widget _customChip() {
    final active = _period == StatsPeriod.custom;
    return GestureDetector(
      onTap: _pickCustomRange,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: Colors.white.withValues(alpha: active ? 0 : 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.date_range,
              size: 12, color: active ? AppColors.primary : Colors.white),
          const SizedBox(width: 4),
          Text('कस्टम',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? AppColors.primary : Colors.white)),
        ]),
      ),
    );
  }

  Widget _headerStat(String label, String value) {
    return Column(children: [
      Text(value,
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 17,
              letterSpacing: -0.5)),
      const SizedBox(height: 3),
      Text(label,
          style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w500)),
    ]);
  }

  Widget _vDivider() => Container(
      height: 32,
      width: 1,
      color: Colors.white.withValues(alpha: 0.2),
      margin: const EdgeInsets.symmetric(horizontal: 8));

  // ── REPORTS BODY ─────────────────────────────────────────────────────────────

  Widget _reportsBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final bills = _filteredBills;
    // Summary cards exclude payment/deposit/cash_loan rows (BUG-13); the
    // bill list rendered below the cards keeps showing every filtered bill,
    // including these types — this fix is scoped to the summary numbers only.
    final summary = computeReportsSalesSummary(bills);
    final creditTotal = summary.creditTotal;
    final cashTotal = summary.cashTotal;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(children: [
            Expanded(
                child: _summaryCard(
                    'नकद बिक्री',
                    cashTotal,
                    summary.cashCount,
                    AppColors.success,
                    AppColors.successLight,
                    Icons.payments_outlined)),
            const SizedBox(width: 10),
            Expanded(
                child: _summaryCard(
                    'उधार बिक्री',
                    creditTotal,
                    summary.creditCount,
                    AppColors.danger,
                    AppColors.dangerLight,
                    Icons.credit_card_outlined)),
          ]),
          const SizedBox(height: 10),
          _summaryCard(
              'कुल बिक्री',
              cashTotal + creditTotal,
              summary.salesCount,
              AppColors.primary,
              AppColors.primaryLight,
              Icons.receipt_long_outlined,
              wide: true),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('बिल इतिहास',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.textPrimary)),
              BillFilterChips(
                selected: _typeFilter,
                onChanged: (f) => setState(() => _typeFilter = f),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (bills.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('इस अवधि में कोई बिल नहीं',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: bills.length,
              itemBuilder: (_, i) => BillCard(bill: bills[i]),
            ),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, double amount, int count, Color color,
      Color bgColor, IconData icon,
      {bool wide = false}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: wide
          ? Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: bgColor, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600)),
                Text(_fmt(amount),
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: color,
                        letterSpacing: -0.5)),
                Text('$count बिल',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
              ]),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: bgColor, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(height: 10),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(_fmt(amount),
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: color,
                      letterSpacing: -0.5)),
              Text('$count बिल',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted)),
            ]),
    );
  }
}
