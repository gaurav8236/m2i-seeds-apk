import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import '../utils/validators.dart';
import '../widgets/bill_card.dart';
import 'add_customer_screen.dart';

// BUG-13: transaction types that are debt collection / advance / loan money,
// not sales revenue — must not contribute to the "नकद बिक्री" / "उधार बिक्री"
// / "कुल बिक्री" summary cards on the Reports tab's 2nd sub-tab. Mirrors the
// exclusion list SupabaseService.fetchFilteredStats() already applies at the
// query level. Deliberately does NOT change how a `split` bill is classified
// here (still whole-amount into उधार बिक्री) — that half is an open
// product-policy question (`.claude/TODOS.md`), not part of this fix.
const _nonSaleTransactionTypes = {'payment', 'deposit', 'cash_loan'};

// Pure summary result for the Reports tab's 3 sales-summary cards. Extracted
// out of `_ReportsScreenState._reportsTab()` (BUG-13) so it can be
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

class ReportsScreen extends StatefulWidget {
  final void Function(VoidCallback) onRegisterReload;
  const ReportsScreen({super.key, required this.onRegisterReload});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;

  // Stats + filter
  StatsPeriod _period = StatsPeriod.thisMonth;
  DateTimeRange? _customRange;
  double _credit = 0, _paid = 0, _outstanding = 0;
  BillTypeFilter _typeFilter = BillTypeFilter.all;

  // Customers
  List<Customer> _customers = [];
  String _customerSearch = '';

  // Reports
  List<Bill> _allBills = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    widget.onRegisterReload(_load);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
      // Perf (Sprint 7, P2-c): fetchTotalOutstanding()/fetchCustomers() now
      // read customers.running_balance directly (O(customer count)) instead
      // of walking past_bills, so neither needs to wait on
      // fetchPastBills() anymore — all four fetches run in one parallel
      // Future.wait instead of two sequential batches.
      final results = await Future.wait([
        SupabaseService.fetchFilteredStats(from: range.start, to: range.end),
        SupabaseService.fetchPastBills(),
        SupabaseService.fetchTotalOutstanding(),
        SupabaseService.fetchCustomers(),
      ]);
      final stats = results[0] as Map<String, double>;
      final bills = results[1] as List<Bill>;
      setState(() {
        _credit = stats['credit'] ?? 0;
        _paid = stats['paid'] ?? 0;
        _outstanding = results[2] as double;
        _customers = results[3] as List<Customer>;
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(children: [
                Row(children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.menu_book,
                        color: Colors.white, size: 17),
                  ),
                  const SizedBox(width: 8),
                  const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('खाता-बही',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                        Text('ग्राहक खाता और रिपोर्ट',
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

                // Stats
                Row(children: [
                  Expanded(child: _headerStat('उधार दिया', _fmt(_credit))),
                  _vDivider(),
                  Expanded(child: _headerStat('नकद जमा', _fmt(_paid))),
                  _vDivider(),
                  Expanded(
                      child: _headerStat('कुल बकाया*', _fmt(_outstanding))),
                ]),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text('* सभी समय का बकाया',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 9)),
                  ),
                ),
                const SizedBox(height: 8),

                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 2),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: Colors.white,
                      labelStyle: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                      unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 13),
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: 'ग्राहक खाता'),
                        Tab(text: 'रिपोर्ट'),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),

        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [_customerTab(), _reportsTab()],
          ),
        ),
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

  // ── CUSTOMER TAB ─────────────────────────────────────────────────────────────

  Widget _customerTab() {
    return RefreshIndicator(
      onRefresh: _load,
      child: Column(children: [
        if (!_loading && _customers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${_customers.length} ग्राहक',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted)),
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AddCustomerScreen()),
                  ).then((_) => _load()),
                  icon: const Icon(Icons.person_add_outlined,
                      size: 16, color: AppColors.primary),
                  label: const Text('+ नया',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppColors.primary)),
                ),
              ],
            ),
          ),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_customers.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.people_outline,
                      size: 56, color: AppColors.border),
                  const SizedBox(height: 14),
                  const Text('कोई ग्राहक नहीं',
                      style: TextStyle(
                          fontSize: 15,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AddCustomerScreen()),
                    ).then((_) => _load()),
                    icon: const Icon(Icons.person_add_outlined, size: 18),
                    label: const Text('+ नया ग्राहक जोड़ें',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              onChanged: (v) => setState(() => _customerSearch = v),
              decoration: const InputDecoration(
                hintText: 'ग्राहक खोजें...',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          Expanded(
            child: Builder(builder: (_) {
              final filtered = _customerSearch.isEmpty
                  ? _customers
                  : _customers
                      .where((c) => c.name
                          .toLowerCase()
                          .contains(_customerSearch.toLowerCase()))
                      .toList();
              if (filtered.isEmpty) {
                return const Center(
                  child: Text('कोई ग्राहक नहीं मिला',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 13)),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: filtered.length,
                itemBuilder: (_, i) => _customerRow(filtered[i]),
              );
            }),
          ),
        ],
      ]),
    );
  }

  Widget _customerRow(Customer customer) {
    final hasOutstanding = customer.outstanding > 0;
    final hasCredit = customer.outstanding < 0; // advance deposit / overpayment
    return GestureDetector(
      onTap: () => _openCustomerDetail(customer),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: hasOutstanding
                  ? AppColors.dangerLight
                  : hasCredit
                      ? AppColors.successLight
                      : AppColors.border),
        ),
        child: Row(children: [
          // Avatar
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasOutstanding
                  ? AppColors.dangerLight
                  : hasCredit
                      ? AppColors.successLight
                      : AppColors.primaryLight,
            ),
            child: Center(
              child: Text(
                customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: hasOutstanding
                        ? AppColors.danger
                        : hasCredit
                            ? AppColors.success
                            : AppColors.primary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name + last purchase
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(customer.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.textPrimary)),
              if (customer.lastPurchaseAt != null)
                Text(
                  DateFormat('dd MMM yyyy').format(customer.lastPurchaseAt!),
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.textMuted),
                )
              else
                const Text('कोई खरीदारी नहीं',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ]),
          ),
          // Outstanding / credit / clear
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              hasOutstanding
                  ? _fmt(customer.outstanding)
                  : hasCredit
                      ? _fmt(customer.outstanding.abs())
                      : 'चुकता',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: hasOutstanding ? AppColors.danger : AppColors.success),
            ),
            if (hasOutstanding)
              const Text('बकाया',
                  style: TextStyle(fontSize: 10, color: AppColors.danger))
            else if (hasCredit)
              const Text('क्रेडिट',
                  style: TextStyle(fontSize: 10, color: AppColors.success)),
          ]),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
        ]),
      ),
    );
  }

  void _openCustomerDetail(Customer customer) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CustomerDetailScreen(customer: customer),
      ),
    ).then((_) => _load());
  }

  // ── REPORTS TAB ──────────────────────────────────────────────────────────────

  Widget _reportsTab() {
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

// ── Customer Detail (inline widget) ─────────────────────────────────────────

class _CustomerDetailScreen extends StatefulWidget {
  final Customer customer;
  // BUG-11 test-only injection seams: _showAddEntryDialog()/_showEditDialog()
  // call these instead of the real SupabaseService network/Supabase calls
  // when non-null, so a widget test can drive both dialogs through their
  // full success + Navigator.pop + dispose sequence deterministically,
  // without a real network call succeeding or failing unpredictably. Mirrors
  // VoiceBillingScreen.initialStockForTest's seam pattern (BUG-5b). Use the
  // @visibleForTesting factory below rather than this private constructor
  // directly from test code.
  final Future<void> Function({required String customerName, required double amount})?
      recordPaymentForTest;
  final Future<void> Function({required String customerName, required double amount})?
      recordDepositForTest;
  final Future<void> Function({required String id, String? phone, double? openingBalance})?
      updateCustomerForTest;

  const _CustomerDetailScreen({
    required this.customer,
    this.recordPaymentForTest,
    this.recordDepositForTest,
    this.updateCustomerForTest,
  });

  @override
  State<_CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

// BUG-11 confirmation-test seam: `_CustomerDetailScreen` is library-private
// (only reachable in production via `_ReportsScreenState._openCustomerDetail`,
// which requires a live Supabase customer list) — this public, @visibleForTesting
// factory lets a widget test build one directly with the injection points
// above, so `_showAddEntryDialog()`/`_showEditDialog()` can be driven through
// their full success/close path without a real Supabase/network call.
@visibleForTesting
Widget customerDetailScreenForTest({
  required Customer customer,
  Future<void> Function({required String customerName, required double amount})?
      recordPayment,
  Future<void> Function({required String customerName, required double amount})?
      recordDeposit,
  Future<void> Function({required String id, String? phone, double? openingBalance})?
      updateCustomer,
}) {
  return _CustomerDetailScreen(
    customer: customer,
    recordPaymentForTest: recordPayment,
    recordDepositForTest: recordDeposit,
    updateCustomerForTest: updateCustomer,
  );
}

class _CustomerDetailScreenState extends State<_CustomerDetailScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _ledger = []; // ascending order (oldest → newest)
  List<double> _runningBalances = []; // running balance AFTER each entry
  List<Bill> _customerBills = [];
  late Customer _customer;

  // BUG-11 fix: these three controllers are State fields, created once and
  // disposed only in this State's own dispose() below — never per dialog
  // open/close. Two earlier candidate fixes (unfocus-before-pop, and
  // deferring dispose() by a single addPostFrameCallback frame) were each
  // confirmed, by `test/reports_screen_customer_dialog_test.dart`, to still
  // leave the controller disposed while its TextField's AnimatedState was
  // mid-closing-transition (the exact BUG-5b mechanism) — a single frame
  // doesn't span a dialog's whole ~150-200ms closing animation. Keeping the
  // controller alive for the screen's entire lifetime removes the race
  // instead of trying to time around it. `_showAddEntryDialog()` clears
  // `_amtCtrl` before reuse; `_showEditDialog()` reseeds `_phoneCtrl`/
  // `_balCtrl` from the current `_customer` before reuse.
  final TextEditingController _amtCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _balCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    _load();
  }

  @override
  void dispose() {
    _amtCtrl.dispose();
    _phoneCtrl.dispose();
    _balCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        SupabaseService.fetchCustomerLedger(_customer.name),
        SupabaseService.fetchCustomerBills(_customer.name),
      ]);
      final ledger = results[0] as List<Map<String, dynamic>>;
      final customerBills = results[1] as List<Bill>;
      if (mounted)
        setState(() {
          _ledger = ledger;
          _customerBills = customerBills;
          _computeRunningBalances();
        });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('लेजर लोड नहीं हो सका: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _computeRunningBalances() {
    double balance = _customer.openingBalance;
    _runningBalances = [];
    for (final entry in _ledger) {
      final type = entry['type'] as String? ?? '';
      final amt = (entry['amount'] as num?)?.toDouble() ?? 0;
      final nagad = (entry['nagad_amount'] as num?)?.toDouble() ?? 0;
      switch (type) {
        case 'credit':
          balance += amt;
          break;
        case 'split':
          balance += (amt - nagad).clamp(0, double.infinity);
          break;
        case 'payment':
        case 'deposit':
          balance -= amt;
          break;
        case 'cash':
        case 'sale':
          break; // already settled — no outstanding impact
      }
      _runningBalances.add(balance);
    }
  }

  // Single source of truth for outstanding — always the balance after the
  // last ledger entry (or the raw opening balance when there's no history
  // yet). Negative = customer has a credit balance (advance deposit / overpayment).
  double get _outstanding => _runningBalances.isEmpty
      ? _customer.openingBalance
      : _runningBalances.last;

  // Tile 1 — "कुल उधार": all-time debt total, including the opening balance
  // (when it's a debt, i.e. positive) plus credit entries plus the udhar
  // portion of split entries. Deliberately excludes plain cash sales — money
  // that was never owed in the first place (BUSINESS_RULES.md's rule against
  // mixing sales and ledger figures).
  double get _totalCreditGiven =>
      (_customer.openingBalance > 0 ? _customer.openingBalance : 0) +
      _ledger.fold<double>(0, (s, e) {
        final type = e['type'] as String? ?? '';
        final amt = (e['amount'] as num?)?.toDouble() ?? 0;
        final nagad = (e['nagad_amount'] as num?)?.toDouble() ?? 0;
        if (type == 'credit') return s + amt;
        if (type == 'split') return s + (amt - nagad).clamp(0, double.infinity);
        return s;
      });

  // Tile 2 — "चुकाया गया": actual debt repayments only — payment + deposit,
  // and nothing else. BUG-7 fix: a split entry's nagad (cash) portion was
  // never added to the debt balance in the first place (see
  // _computeRunningBalances' split case below, which only adds the udhar
  // portion) — so it can't be "repaid," exactly like a plain 'cash'/'sale'
  // amount. Counting it here (the original plan's Part 3 formula) broke
  // Tile1 − Tile2 == Tile3 reconciliation whenever a split entry existed.
  double get _totalReceived => _ledger.fold<double>(0, (s, e) {
        final type = e['type'] as String? ?? '';
        final amt = (e['amount'] as num?)?.toDouble() ?? 0;
        if (type == 'payment' || type == 'deposit') return s + amt;
        return s;
      });

  // Bug #55: ₹3,090 was showing as ₹3.0k — threshold was too low.
  // Now: below ₹1L shows full Indian-comma format (₹3,090 / ₹13,184);
  // ₹1L+ shows compact (₹1.5L).
  String _fmt(double n) {
    if (n >= 100000) return '₹${(n / 100000).toStringAsFixed(1)}L';
    return '₹${NumberFormat('#,##,##0', 'en_IN').format(n.round())}';
  }

  Future<void> _showAddEntryDialog() async {
    String entryType = 'payment';
    // BUG-11 fix: reuse the State-level controller (never disposed per
    // dialog) instead of creating+disposing a local one — see field comment.
    final amtCtrl = _amtCtrl..clear();
    final amtFormKey = GlobalKey<FormState>();
    // 'submitting' is declared OUTSIDE the StatefulBuilder so it is not
    // re-initialised to false whenever the payment/deposit chip toggle calls
    // setLocal() and rebuilds the closure (same fix applied to _showEditDialog).
    bool submitting = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('लेन-देन का प्रकार चुनें',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            content: Form(
              key: amtFormKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _entryOption(
                  label: 'भुगतान मिला',
                  sub: 'ग्राहक ने बकाया चुकाया',
                  icon: Icons.arrow_downward,
                  value: 'payment',
                  selected: entryType,
                  color: AppColors.success,
                  bgColor: AppColors.successLight,
                  onTap: () => setLocal(() => entryType = 'payment'),
                ),
                const SizedBox(height: 8),
                _entryOption(
                  label: 'अग्रिम जमा',
                  sub: 'ग्राहक ने पहले से पैसा दिया',
                  icon: Icons.savings_outlined,
                  value: 'deposit',
                  selected: entryType,
                  color: AppColors.advanceViolet,
                  bgColor: AppColors.advanceVioletLight,
                  onTap: () => setLocal(() => entryType = 'deposit'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: amtCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    prefixText: '₹  ',
                    labelText: 'राशि',
                    hintText: 'जैसे: 500',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => Validators.paymentAmount(v),
                ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('रद्द करें',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
              // Single setLocal drives both chip toggles and the submitting
              // state — no nested builder so 'submitting' is never re-initialised.
              ElevatedButton(
                onPressed: submitting
                    ? null
                    : () async {
                        if (!amtFormKey.currentState!.validate()) return;
                        final amt = double.parse(amtCtrl.text.trim());
                        setLocal(() => submitting = true);
                        try {
                          if (entryType == 'payment') {
                            final record = widget.recordPaymentForTest ??
                                SupabaseService.recordPayment;
                            await record(
                                customerName: widget.customer.name,
                                amount: amt);
                          } else {
                            final record = widget.recordDepositForTest ??
                                SupabaseService.recordDeposit;
                            await record(
                                customerName: widget.customer.name,
                                amount: amt);
                          }
                          // BUG-11, hypothesis #2 (#1's frame-deferral alone did
                          // not hold on retest): the amount field almost
                          // certainly still has focus (active cursor-blink
                          // animation) at the moment of submit — unfocus before
                          // popping, matching BUG-5b's actual confirmed
                          // mechanism (a focused field's AnimatedState colliding
                          // with route teardown), not just a timing guess.
                          if (ctx.mounted) FocusScope.of(ctx).unfocus();
                          if (ctx.mounted) Navigator.pop(ctx);
                          // BUG-11 candidate fix: defer the post-pop reload (and its
                          // setState) past the dialog's closing transition instead of
                          // awaiting it immediately after Navigator.pop — same class of
                          // race as BUG-5b (a full-screen rebuild landing mid-transition
                          // on a still-closing route), not yet reproduction-confirmed.
                          WidgetsBinding.instance.addPostFrameCallback((_) async {
                            await _load();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(
                                      '₹${amt.toStringAsFixed(0)} दर्ज किया')));
                            }
                          });
                        } catch (e) {
                          setLocal(() => submitting = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('त्रुटि: $e')));
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : const Text('दर्ज करें',
                        style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );
    // BUG-11 fix: no per-dialog dispose() anymore — `_amtCtrl` is a
    // State-level field, disposed only in this State's own dispose(). See
    // the field's doc comment for why the earlier addPostFrameCallback-
    // deferral approach was confirmed insufficient.
  }

  // ── C-05: Edit customer ────────────────────────────────────────────────────
  Future<void> _showEditDialog() async {
    // Name locked if the customer has any past bills (credit / cash / split)
    final hasBills = _ledger
        .any((e) => ['credit', 'cash', 'split'].contains(e['type'] as String?));

    // BUG-11 fix: reuse the State-level controllers (never disposed per
    // dialog) instead of creating+disposing local ones — see field comment.
    final phoneCtrl = _phoneCtrl..text = widget.customer.phone ?? '';
    final balCtrl = _balCtrl
      ..text = widget.customer.openingBalance.abs().toStringAsFixed(0);
    // true = debt (positive), false = advance (negative)
    bool isDebt = widget.customer.openingBalance >= 0;
    // 'saving' is declared OUTSIDE the StatefulBuilder so it is not
    // re-initialised to false every time setDialog() rebuilds the widget
    // (e.g. when the user toggles the उधार/अग्रिम chips).
    bool saving = false;
    final editFormKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              const Icon(Icons.edit_outlined,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.customer.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ]),
            content: SingleChildScrollView(
              child: Form(
                key: editFormKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // Name locked if bills exist
                  if (hasBills)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.warningLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.warning.withOpacity(0.4)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.lock_outline,
                            size: 14, color: AppColors.warning),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'पिछले बिल होने के कारण नाम नहीं बदला जा सकता',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.warning),
                          ),
                        ),
                      ]),
                    ),
                  if (hasBills) const SizedBox(height: 12),

                  // Phone
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'मोबाइल नंबर',
                      prefixIcon: Icon(Icons.phone_outlined, size: 16),
                      isDense: true,
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return null;
                      if (v.length != 10) return '10 अंक ज़रूरी हैं';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Opening balance type
                  Row(children: [
                    Expanded(
                      child: _balanceChip(
                        label: 'उधार',
                        active: isDebt,
                        color: AppColors.danger,
                        bgColor: AppColors.dangerLight,
                        onTap: () => setDialog(() => isDebt = true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _balanceChip(
                        label: 'अग्रिम',
                        active: !isDebt,
                        color: AppColors.advanceViolet,
                        bgColor: AppColors.advanceVioletLight,
                        onTap: () => setDialog(() => isDebt = false),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: balCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'शुरुआती बैलेंस',
                      prefixText: '₹ ',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return null;
                      if (double.tryParse(v) == null) return 'सही राशि डालें';
                      return null;
                    },
                  ),
                ]),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('रद्द करें',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
              // Single StatefulBuilder (setDialog) drives both chip toggles
              // and the saving state — no nested builder so 'saving' is never
              // re-initialised on chip-toggle rebuilds.
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!editFormKey.currentState!.validate()) return;
                        setDialog(() => saving = true);
                        try {
                          final raw = double.tryParse(balCtrl.text) ?? 0;
                          final ob = isDebt ? raw : -raw;
                          final ph =
                              phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
                          final update = widget.updateCustomerForTest ??
                              SupabaseService.updateCustomer;
                          await update(
                            id: widget.customer.id,
                            phone: ph,
                            openingBalance: ob,
                          );
                          // Same hypothesis-#2 fix as _showAddEntryDialog —
                          // unfocus before popping (see that function's comment).
                          if (ctx.mounted) FocusScope.of(ctx).unfocus();
                          if (ctx.mounted) Navigator.pop(ctx);
                          // BUG-11-class candidate fix: defer the post-pop
                          // reload/snackbar past the dialog's closing transition,
                          // same reasoning as _showAddEntryDialog — not yet
                          // reproduction-confirmed for this dialog specifically.
                          WidgetsBinding.instance.addPostFrameCallback((_) async {
                            // Fix #5: confirm save to the shopkeeper
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('बदलाव सहेज दिए गए')));
                            }
                            await _load();
                          });
                        } catch (e) {
                          setDialog(() => saving = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('त्रुटि: $e')));
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : const Text('सहेजें',
                        style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );
    // BUG-11 fix: no per-dialog dispose() anymore — `_phoneCtrl`/`_balCtrl`
    // are State-level fields, disposed only in this State's own dispose().
    // See `_amtCtrl`'s field doc comment for why the earlier
    // addPostFrameCallback-deferral approach was confirmed insufficient.
  }

  // Small chip used in the edit dialog
  Widget _balanceChip({
    required String label,
    required bool active,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? bgColor : AppColors.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active ? color : AppColors.border,
              width: active ? 1.5 : 1),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? color : AppColors.textSecondary)),
      ),
    );
  }

  // ── C-06: Delete customer ──────────────────────────────────────────────────
  Future<void> _confirmDelete() async {
    // Hard block: cannot delete while outstanding ≠ 0.
    // Use a 0.50 epsilon — amounts are whole rupees so any sub-rupee
    // residual is floating-point noise from accumulated arithmetic.
    if (_outstanding.abs() >= 0.50) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.block, color: AppColors.danger, size: 20),
            SizedBox(width: 8),
            Text('हटाना संभव नहीं',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ]),
          content: Text(
            'ग्राहक पर अभी '
            '${_outstanding > 0 ? "₹${_outstanding.toStringAsFixed(0)} बकाया" : "₹${_outstanding.abs().toStringAsFixed(0)} अग्रिम जमा"} '
            'है। पहले इसे शून्य करें, फिर हटाएं।',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ठीक है'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${widget.customer.name} को हटाएं?',
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ]),
        content: const Text(
          'यह ग्राहक और उसका पूरा लेनदेन इतिहास हमेशा के लिए हट जाएगा। '
          'क्या आप सुनिश्चित हैं?',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('रद्द करें',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('हटाएं',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await SupabaseService.deleteCustomer(widget.customer.id);
      if (mounted) {
        Navigator.pop(context); // go back to customer list
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${widget.customer.name} हटाया गया')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('हटाने में त्रुटि: $e')));
      }
    }
  }

  Widget _entryOption({
    required String label,
    required String sub,
    required IconData icon,
    required String value,
    required String selected,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    final active = selected == value;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? bgColor : AppColors.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: active ? color : AppColors.border,
              width: active ? 1.5 : 1),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: active ? color : AppColors.textMuted),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: active ? color : AppColors.textPrimary)),
            Text(sub,
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final outstanding = _outstanding;
    final isCredit = outstanding < 0;
    final isClear = outstanding == 0;
    final balLabel =
        isCredit ? 'क्रेडिट बैलेंस' : (isClear ? 'चुकता' : 'कुल बकाया');

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(children: [
        // ── Header ──────────────────────────────────────────────────────────
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
              child: Column(children: [
                // Back row + action buttons
                Row(children: [
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
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_customer.name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16),
                              overflow: TextOverflow.ellipsis),
                          Row(children: [
                            if (_customer.phone != null &&
                                _customer.phone!.isNotEmpty) ...[
                              const Icon(Icons.phone,
                                  color: Colors.white70, size: 11),
                              const SizedBox(width: 3),
                              Text(_customer.phone!,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 11)),
                              const SizedBox(width: 10),
                            ],
                            if (_customer.openingBalance > 0) ...[
                              const Icon(Icons.account_balance_wallet_outlined,
                                  color: Colors.white70, size: 11),
                              const SizedBox(width: 3),
                              Text(
                                  'शुरुआती: ₹${_customer.openingBalance.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 11)),
                            ] else
                              const Text('ग्राहक खाता',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 11)),
                          ]),
                        ]),
                  ),
                  // C-05 / C-06: edit & delete menu
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    onSelected: (v) {
                      if (v == 'edit') _showEditDialog();
                      if (v == 'delete') _confirmDelete();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(children: [
                          Icon(Icons.edit_outlined,
                              size: 16, color: AppColors.primary),
                          SizedBox(width: 10),
                          Text('संपादित करें',
                              style: TextStyle(color: AppColors.textPrimary)),
                        ]),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete_outline,
                              size: 16, color: AppColors.danger),
                          SizedBox(width: 10),
                          Text('हटाएं',
                              style: TextStyle(color: AppColors.danger)),
                        ]),
                      ),
                    ],
                  ),
                ]),
                const SizedBox(height: 12),

                // लेन-देन दर्ज करें — full-width, solid-fill primary action.
                // Deliberately the only solid-white control in this header
                // (back button and ⋮ stay translucent) so it reads as the
                // primary action, distinct from the edit/delete menu.
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: _showAddEntryDialog,
                    icon: const Icon(Icons.add,
                        size: 18, color: AppColors.primary),
                    label: const Text('लेन-देन दर्ज करें',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 3-tile summary card
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: _hStat('कुल उधार',
                          _loading ? '—' : _fmt(_totalCreditGiven)),
                    ),
                    Container(
                        height: 30,
                        width: 1,
                        color: Colors.white.withOpacity(0.2)),
                    Expanded(
                      child: _hStat(
                          'चुकाया गया', _loading ? '—' : _fmt(_totalReceived)),
                    ),
                    Container(
                        height: 30,
                        width: 1,
                        color: Colors.white.withOpacity(0.2)),
                    Expanded(
                      child: _hStat(
                        balLabel,
                        _loading
                            ? '—'
                            : (isCredit
                                ? _fmt(outstanding.abs())
                                : _fmt(outstanding)),
                        highlight: true,
                        isGreen: isCredit || isClear,
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),

        // ── Body ────────────────────────────────────────────────────────────
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  // Ledger card
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                        child: Row(children: [
                          const Expanded(
                            child: Text('लेनदेन इतिहास',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textMuted,
                                    letterSpacing: 0.5)),
                          ),
                          Text('${_ledger.length} लेनदेन',
                              style: const TextStyle(
                                  fontSize: 10, color: AppColors.textMuted)),
                        ]),
                      ),
                      if (_ledger.isEmpty &&
                          widget.customer.openingBalance == 0)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                            child: Text('कोई लेनदेन नहीं',
                                style: TextStyle(
                                    color: AppColors.textMuted, fontSize: 13)),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          // Newest-first display + opening balance row at bottom
                          // Show opening balance row for both debt (+) and advance (-)
                          itemCount: _ledger.length +
                              (widget.customer.openingBalance != 0 ? 1 : 0),
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, color: AppColors.border),
                          itemBuilder: (_, i) {
                            // Last row = opening balance (debt OR advance)
                            if (widget.customer.openingBalance != 0 &&
                                i == _ledger.length) {
                              return _openingBalanceRow();
                            }
                            // Reverse ledger index for newest-first display
                            final idx = _ledger.length - 1 - i;
                            return _ledgerRow(
                                _ledger[idx], _runningBalances[idx]);
                          },
                        ),
                    ]),
                  ),

                  // Bills of this customer
                  if (_customerBills.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('बिल इतिहास',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textMuted,
                                letterSpacing: 0.5)),
                      ),
                    ),
                    ..._customerBills.map((b) => BillCard(bill: b)),
                  ],
                  const SizedBox(height: 24),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  // NOTE (merge/unified-v1): the old single-arg _ledgerRow(entry) that lived
  // here was superseded by the two-arg _ledgerRow(entry, runningBalance)
  // below — its type-based color/icon/label switch was carried over there
  // so nothing from Sprint 9's visual treatment was lost.
  Widget _hStat(String label, String value,
      {bool highlight = false, bool isGreen = false}) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(value,
          style: TextStyle(
              color: highlight
                  ? (isGreen ? AppColors.successOnDark : Colors.white)
                  : Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: highlight ? 16 : 14,
              letterSpacing: -0.5)),
      const SizedBox(height: 3),
      Text(label,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 9,
              fontWeight: FontWeight.w500),
          textAlign: TextAlign.center),
    ]);
  }

  Widget _openingBalanceRow() {
    final ob = widget.customer.openingBalance;
    final isDebt = ob > 0; // customer owes us
    final isAdv = ob < 0; // customer pre-paid (advance)
    final color = isDebt ? AppColors.danger : AppColors.advanceViolet;
    final bgColor =
        isDebt ? AppColors.dangerLight : AppColors.advanceVioletLight;
    final icon =
        isAdv ? Icons.savings_outlined : Icons.account_balance_wallet_outlined;
    final sign = isDebt ? '+' : '-';
    final label = isDebt ? 'शुरुआती बकाया' : 'शुरुआती अग्रिम';
    final sublabel = isDebt ? 'Opening Debt Balance' : 'Advance Pre-payment';
    final balLabel = isDebt ? 'उधार' : 'अग्रिम';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bgColor),
        child: Icon(icon, size: 18, color: color),
      ),
      title: Text(label,
          style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: 13, color: color)),
      subtitle: Text(sublabel,
          style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('$sign₹${ob.abs().toStringAsFixed(0)}',
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13, color: color)),
          Text(balLabel, style: TextStyle(fontSize: 9, color: color)),
        ],
      ),
    );
  }

  Widget _ledgerRow(Map<String, dynamic> entry, double runningBalance) {
    final type = entry['type'] as String? ?? '';
    final amt = (entry['amount'] as num?)?.toDouble() ?? 0;
    final nagad = (entry['nagad_amount'] as num?)?.toDouble() ?? 0;
    final date = entry['created_at'] != null
        ? DateTime.tryParse(entry['created_at'] as String)
        : null;

    Color rowColor;
    IconData rowIcon;
    String rowLabel;
    String amtText;

    switch (type) {
      case 'split':
        rowColor = AppColors.warning;
        rowIcon = Icons.call_split;
        rowLabel = 'आंशिक नकद+उधार';
        final udhar = (amt - nagad).clamp(0, double.infinity);
        amtText =
            '₹${nagad.toStringAsFixed(0)} नकद · ₹${udhar.toStringAsFixed(0)} उधार';
        break;
      case 'payment':
        rowColor = AppColors.success;
        rowIcon = Icons.arrow_downward;
        rowLabel = 'भुगतान मिला';
        amtText = '-₹${amt.toStringAsFixed(0)}';
        break;
      case 'deposit':
        rowColor = AppColors.advanceViolet;
        rowIcon = Icons.savings_outlined;
        rowLabel = 'अग्रिम जमा';
        amtText = '-₹${amt.toStringAsFixed(0)}';
        break;
      case 'cash':
      case 'sale':
        rowColor = AppColors.success;
        rowIcon = Icons.payments_outlined;
        rowLabel = 'नकद बिक्री';
        amtText = '₹${amt.toStringAsFixed(0)}';
        break;
      default: // 'credit'
        rowColor = AppColors.danger;
        rowIcon = Icons.arrow_upward;
        rowLabel = 'उधार';
        amtText = '+₹${amt.toStringAsFixed(0)}';
    }

    // Running balance annotation per row
    final balIsCredit = runningBalance < 0;
    final balColor = balIsCredit
        ? AppColors.success
        : (runningBalance > 0 ? AppColors.danger : AppColors.success);
    final balText = balIsCredit
        ? 'क्रेडिट ${_fmt(runningBalance.abs())}'
        : (runningBalance > 0 ? 'बकाया ${_fmt(runningBalance)}' : 'चुकता ✓');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: rowColor.withOpacity(0.12),
        ),
        child: Icon(rowIcon, size: 18, color: rowColor),
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(rowLabel,
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13, color: rowColor),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Text(amtText,
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13, color: rowColor)),
        ],
      ),
      subtitle: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            date != null
                ? DateFormat('dd MMM, hh:mm a').format(date.toLocal())
                : '—',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          Text(balText,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, color: balColor)),
        ],
      ),
    );
  }
}
