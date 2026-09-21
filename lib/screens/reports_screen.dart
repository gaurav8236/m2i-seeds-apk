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

// One row of the Reports screen's "ग्राहक" view: every bill for a customer
// rolled up into a count and a total.
@visibleForTesting
class CustomerBillTotal {
  final String name;
  final int billCount;
  final double totalAmount;
  const CustomerBillTotal({
    required this.name,
    required this.billCount,
    required this.totalAmount,
  });
}

// Groups `bills` (already period/type-filtered by the caller) by customer,
// largest total first. Names are matched case-insensitively on the trimmed
// value (same rule as ensureCustomerExists, #58); bills with no customer name
// are grouped as "नकद ग्राहक", matching BillCard. payment/deposit/cash_loan
// rows are excluded (BUG-13) — they are not sales.
@visibleForTesting
List<CustomerBillTotal> aggregateBillsByCustomer(List<Bill> bills) {
  final groups = <String, ({String name, int count, double total})>{};
  for (final b in bills) {
    if (_nonSaleTransactionTypes.contains(b.transactionType)) continue;
    final name = (b.customerName ?? '').trim();
    final key = name.toLowerCase();
    final prev = groups[key];
    groups[key] = (
      // First-seen casing is kept for display.
      name: prev?.name ?? (name.isEmpty ? 'नकद ग्राहक' : name),
      count: (prev?.count ?? 0) + 1,
      total: (prev?.total ?? 0) + b.totalAmount,
    );
  }
  return groups.values
      .map((g) => CustomerBillTotal(
          name: g.name, billCount: g.count, totalAmount: g.total))
      .toList()
    ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
}

enum _ReportView { bills, customers }

// ── Reports screen ───────────────────────────────────────────────────────────
//
// Sales reporting only — period filters + a बिल / ग्राहक switch (every bill,
// or totals per customer). The customer-ledger tab (customer list, outstanding balances,
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
  double _credit = 0, _paid = 0;
  BillTypeFilter _typeFilter = BillTypeFilter.all;
  _ReportView _view = _ReportView.bills;

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
      // Use exclusive-midnight upper bounds for all periods. DateTime handles
      // day/month overflow correctly (e.g. day 32 → next month, month 13 → next
      // year).  fetchFilteredStats converts these local (IST) DateTimes to UTC
      // before the Supabase query. (#47)
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
                  ]),
                ),
                const SizedBox(height: 12),

                // Stats — all three follow the period chips above and come from
                // the same fetchFilteredStats() call, so कुल बिक्री is always
                // exactly उधार दिया + नकद जमा. No all-time outstanding/balance
                // figure — see file header note.
                Row(children: [
                  Expanded(child: _headerStat('उधार दिया', _fmt(_credit))),
                  _vDivider(),
                  Expanded(child: _headerStat('नकद जमा', _fmt(_paid))),
                  _vDivider(),
                  Expanded(
                      child: _headerStat('कुल बिक्री', _fmt(_credit + _paid))),
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
    final customers =
        _view == _ReportView.customers ? aggregateBillsByCustomer(bills) : [];
    final isBills = _view == _ReportView.bills;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(children: [
            Expanded(
                child: _viewButton('बिल', Icons.receipt_long_outlined,
                    _ReportView.bills)),
            const SizedBox(width: 10),
            Expanded(
                child: _viewButton('ग्राहक', Icons.people_outline,
                    _ReportView.customers)),
          ]),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(isBills ? 'बिल इतिहास' : 'ग्राहक अनुसार कुल',
                  style: const TextStyle(
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
          if (isBills && bills.isEmpty || !isBills && customers.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('इस अवधि में कोई बिल नहीं',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
            )
          else if (isBills)
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: bills.length,
              itemBuilder: (_, i) => BillCard(bill: bills[i]),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: customers.length,
              itemBuilder: (_, i) => _customerRow(customers[i]),
            ),
        ],
      ),
    );
  }

  Widget _viewButton(String label, IconData icon, _ReportView view) {
    final active = _view == view;
    return GestureDetector(
      onTap: () => setState(() => _view = view),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: active ? AppColors.primary : AppColors.border),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon,
              size: 18, color: active ? Colors.white : AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : AppColors.textSecondary)),
        ]),
      ),
    );
  }

  Widget _customerRow(CustomerBillTotal c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
              shape: BoxShape.circle, color: AppColors.primaryLight),
          child: Center(
            child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.primary)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.textPrimary)),
            Text('${c.billCount} बिल',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
        ),
        Text(_fmt(c.totalAmount),
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AppColors.primary)),
      ]),
    );
  }
}
