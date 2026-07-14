import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import 'add_customer_screen.dart';

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
  StatsPeriod _period = StatsPeriod.today;
  DateTimeRange? _customRange;
  double _credit = 0, _paid = 0, _outstanding = 0;

  // Customers
  List<Customer> _customers = [];

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
      case StatsPeriod.today:
        return DateTimeRange(
            start: DateTime(now.year, now.month, now.day), end: now);
      case StatsPeriod.thisWeek:
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return DateTimeRange(
            start: DateTime(monday.year, monday.month, monday.day), end: now);
      case StatsPeriod.thisMonth:
        return DateTimeRange(
            start: DateTime(now.year, now.month, 1), end: now);
      case StatsPeriod.custom:
        return _customRange ??
            DateTimeRange(
                start: DateTime(now.year, now.month, 1), end: now);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final range = _rangeFor(_period);
      final results = await Future.wait([
        SupabaseService.fetchFilteredStats(from: range.start, to: range.end),
        SupabaseService.fetchTotalOutstanding(),
        SupabaseService.fetchCustomers(),
        SupabaseService.fetchPastBills(),
      ]);
      final stats = results[0] as Map<String, double>;
      setState(() {
        _credit = stats['credit'] ?? 0;
        _paid = stats['paid'] ?? 0;
        _outstanding = results[1] as double;
        _customers = results[2] as List<Customer>;
        _allBills = results[3] as List<Bill>;
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
            b.createdAt.isBefore(range.end.add(const Duration(days: 1))))
        .toList();
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  String _fmt(double n) =>
      n >= 1000 ? '₹${(n / 1000).toStringAsFixed(1)}k' : '₹${n.toStringAsFixed(0)}';

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
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.menu_book, color: Colors.white, size: 17),
                  ),
                  const SizedBox(width: 8),
                  const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('खाता-बही',
                        style: TextStyle(color: Colors.white,
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    Text('Ledger & Reports',
                        style: TextStyle(color: Colors.white70, fontSize: 10)),
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
                  Expanded(child: _headerStat('कुल बकाया', _fmt(_outstanding))),
                ]),
                const SizedBox(height: 12),

                TabBar(
                  controller: _tabController,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  indicatorColor: Colors.white,
                  indicatorWeight: 2.5,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                  tabs: const [
                    Tab(text: 'ग्राहक खाता'),
                    Tab(text: 'रिपोर्ट'),
                  ],
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
          color: active ? Colors.white : Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: Colors.white.withOpacity(active ? 0 : 0.3)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
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
          color: active ? Colors.white : Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: Colors.white.withOpacity(active ? 0 : 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.date_range, size: 12,
              color: active ? AppColors.primary : Colors.white),
          const SizedBox(width: 4),
          Text('कस्टम',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: active ? AppColors.primary : Colors.white)),
        ]),
      ),
    );
  }

  Widget _headerStat(String label, String value) {
    return Column(children: [
      Text(value,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800,
              fontSize: 17, letterSpacing: -0.5)),
      const SizedBox(height: 3),
      Text(label,
          style: const TextStyle(
              color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500)),
    ]);
  }

  Widget _vDivider() => Container(
        height: 32, width: 1,
        color: Colors.white.withOpacity(0.2),
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
                        fontSize: 12, fontWeight: FontWeight.w600,
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
                          fontWeight: FontWeight.w700, fontSize: 13,
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
                          fontSize: 15, color: AppColors.textMuted,
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
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
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
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _customers.length,
              itemBuilder: (_, i) => _customerRow(_customers[i]),
            ),
          ),
      ]),
    );
  }

  Widget _customerRow(Customer customer) {
    final hasOutstanding = customer.outstanding > 0;
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
                  ? const Color(0xFFFFCACA)
                  : AppColors.border),
        ),
        child: Row(children: [
          // Avatar
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasOutstanding
                  ? AppColors.dangerLight
                  : AppColors.primaryLight,
            ),
            child: Center(
              child: Text(
                customer.name.isNotEmpty
                    ? customer.name[0].toUpperCase()
                    : '?',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16,
                    color: hasOutstanding
                        ? AppColors.danger
                        : AppColors.primary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name + last purchase
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(customer.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14,
                      color: AppColors.textPrimary)),
              if (customer.lastPurchaseAt != null)
                Text(
                  DateFormat('dd MMM yyyy').format(customer.lastPurchaseAt!),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted),
                )
              else
                const Text('कोई खरीदारी नहीं',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
            ]),
          ),
          // Outstanding or clear
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              hasOutstanding ? _fmt(customer.outstanding) : 'बकाया नहीं',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: hasOutstanding
                      ? AppColors.danger
                      : AppColors.success),
            ),
            if (hasOutstanding)
              const Text('बकाया',
                  style: TextStyle(fontSize: 10, color: AppColors.danger)),
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
    final creditBills = bills.where((b) => b.isCredit).toList();
    final cashBills = bills.where((b) => !b.isCredit).toList();
    final creditTotal = creditBills.fold(0.0, (s, b) => s + b.totalAmount);
    final cashTotal = cashBills.fold(0.0, (s, b) => s + b.totalAmount);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(children: [
            Expanded(child: _summaryCard('नकद बिक्री', cashTotal,
                cashBills.length, AppColors.success, AppColors.successLight,
                Icons.payments_outlined)),
            const SizedBox(width: 10),
            Expanded(child: _summaryCard('उधार बिक्री', creditTotal,
                creditBills.length, AppColors.danger, AppColors.dangerLight,
                Icons.credit_card_outlined)),
          ]),
          const SizedBox(height: 10),
          _summaryCard('कुल बिक्री', cashTotal + creditTotal, bills.length,
              AppColors.primary, AppColors.primaryLight,
              Icons.receipt_long_outlined, wide: true),
          const SizedBox(height: 20),
          const Text('बिल इतिहास',
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13,
                  color: AppColors.textPrimary)),
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
              itemBuilder: (_, i) => _billCard(bills[i]),
            ),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, double amount, int count, Color color,
      Color bgColor, IconData icon, {bool wide = false}) {
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
                width: 40, height: 40,
                decoration: BoxDecoration(
                    color: bgColor, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted,
                        fontWeight: FontWeight.w600)),
                Text(_fmt(amount),
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 20,
                        color: color, letterSpacing: -0.5)),
                Text('$count बिल',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
              ]),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: bgColor, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(height: 10),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(_fmt(amount),
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 18,
                      color: color, letterSpacing: -0.5)),
              Text('$count बिल',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted)),
            ]),
    );
  }

  Widget _billCard(Bill bill) {
    final color = bill.isCredit ? AppColors.danger : AppColors.success;
    final bgColor = bill.isCredit ? AppColors.dangerLight : AppColors.successLight;
    final icon = bill.isCredit ? Icons.credit_card_outlined : Icons.payments_outlined;

    return GestureDetector(
      onTap: () => _showBillDetail(bill),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(bill.customerName ?? 'नकद ग्राहक',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13,
                      color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(
                '${DateFormat('dd MMM, hh:mm a').format(bill.createdAt)} · ${bill.billDetails.length} आइटम',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_fmt(bill.totalAmount),
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14, color: color)),
            Text(bill.isCredit ? 'उधार' : 'नकद',
                style: TextStyle(fontSize: 10, color: color)),
          ]),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
        ]),
      ),
    );
  }

  void _showBillDetail(Bill bill) {
    final color = bill.isCredit ? AppColors.danger : AppColors.success;
    final bgColor = bill.isCredit ? AppColors.dangerLight : AppColors.successLight;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (_, scrollCtrl) => Container(
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
                  borderRadius: BorderRadius.circular(2)),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                      color: bgColor, borderRadius: BorderRadius.circular(10)),
                  child: Icon(
                    bill.isCredit ? Icons.credit_card_outlined : Icons.payments_outlined,
                    color: color, size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(bill.customerName ?? 'नकद ग्राहक',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15,
                            color: AppColors.textPrimary)),
                    Text(DateFormat('dd MMM yyyy, hh:mm a').format(bill.createdAt),
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: bgColor, borderRadius: BorderRadius.circular(20)),
                  child: Text(bill.isCredit ? 'उधार' : 'नकद',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: color)),
                ),
              ]),
            ),
            const Divider(height: 1, color: AppColors.border),
            // Items list
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('आइटम',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700,
                          color: AppColors.textMuted, letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  ...bill.billDetails.map((item) {
                    final name = item['item_name']?.toString() ?? '';
                    final qty = (item['quantity_billed'] as num?)?.toDouble() ?? 0;
                    final price = (item['price_per_unit'] as num?)?.toDouble() ?? 0;
                    final total = (item['item_total'] as num?)?.toDouble() ?? 0;
                    final unit = item['unit']?.toString() ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13,
                                    color: AppColors.textPrimary)),
                            Text('$qty $unit × ₹${price.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.textMuted)),
                          ]),
                        ),
                        Text('₹${total.toStringAsFixed(0)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13,
                                color: AppColors.textPrimary)),
                      ]),
                    );
                  }),
                  const Divider(color: AppColors.border),
                  if (bill.discountAmount != null && bill.discountAmount! > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('छूट',
                              style: TextStyle(
                                  fontSize: 13, color: AppColors.textMuted)),
                          Text('- ₹${bill.discountAmount!.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontSize: 13, color: AppColors.danger,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('कुल',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15,
                              color: AppColors.textPrimary)),
                      Text(_fmt(bill.totalAmount),
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 18,
                              color: color, letterSpacing: -0.5)),
                    ],
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Customer Detail (inline widget) ─────────────────────────────────────────

class _CustomerDetailScreen extends StatefulWidget {
  final Customer customer;
  const _CustomerDetailScreen({required this.customer});

  @override
  State<_CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<_CustomerDetailScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _ledger = [];
  final _payCtrl = TextEditingController();
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _payCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data =
          await SupabaseService.fetchCustomerLedger(widget.customer.name);
      setState(() => _ledger = data);
    } finally {
      setState(() => _loading = false);
    }
  }

  double get _outstanding {
    return _ledger.fold<double>(0, (s, e) {
      final amt = (e['amount'] as num?)?.toDouble() ?? 0;
      return e['type'] == 'credit' ? s + amt : s - amt;
    }).clamp(0, double.infinity);
  }

  Future<void> _recordPayment() async {
    final amt = double.tryParse(_payCtrl.text);
    if (amt == null || amt <= 0) return;
    setState(() => _paying = true);
    try {
      await SupabaseService.recordPayment(
          customerName: widget.customer.name, amount: amt);
      _payCtrl.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('₹${amt.toStringAsFixed(0)} दर्ज किया')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('त्रुटि: $e')));
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  String _fmt(double n) =>
      n >= 1000 ? '₹${(n / 1000).toStringAsFixed(1)}k' : '₹${n.toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(children: [
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
                Row(children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.customer.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                    const Text('ग्राहक खाता',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ]),
                ]),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('कुल बकाया',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      Text(
                        _loading ? '—' : _fmt(_outstanding),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 26,
                            fontWeight: FontWeight.w800, letterSpacing: -1),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),

        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                // Payment section
                if (_outstanding > 0)
                  Container(
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFDE68A),
                          width: 1.5),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('भुगतान दर्ज करें',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700,
                              color: AppColors.textMuted,
                              letterSpacing: 0.4)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _payCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                prefixText: '₹',
                                hintText: 'राशि',
                                isDense: true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _paying ? null : _recordPayment,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: _paying
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5))
                              : const Text('दर्ज',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    ]),
                  ),

                // Transaction history
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(14, 12, 14, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('लेनदेन इतिहास',
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w700,
                                color: AppColors.textMuted,
                                letterSpacing: 0.5)),
                      ),
                    ),
                    if (_ledger.isEmpty)
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
                        itemCount: _ledger.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: AppColors.border),
                        itemBuilder: (_, i) => _ledgerRow(_ledger[i]),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _ledgerRow(Map<String, dynamic> entry) {
    final type = entry['type'] as String? ?? '';
    final amt = (entry['amount'] as num?)?.toDouble() ?? 0;
    final date = entry['created_at'] != null
        ? DateTime.tryParse(entry['created_at'] as String)
        : null;
    final isCredit = type == 'credit';

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isCredit ? AppColors.dangerLight : AppColors.successLight,
        ),
        child: Icon(
          isCredit ? Icons.arrow_upward : Icons.arrow_downward,
          size: 18,
          color: isCredit ? AppColors.danger : AppColors.success,
        ),
      ),
      title: Text(isCredit ? 'उधार' : 'भुगतान',
          style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: 13,
              color: isCredit ? AppColors.danger : AppColors.success)),
      subtitle: date != null
          ? Text(DateFormat('dd MMM, hh:mm a').format(date),
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textMuted))
          : null,
      trailing: Text(
        '${isCredit ? '+' : '-'}₹${amt.toStringAsFixed(0)}',
        style: TextStyle(
            fontWeight: FontWeight.w800, fontSize: 15,
            color: isCredit ? AppColors.danger : AppColors.success),
      ),
    );
  }
}
