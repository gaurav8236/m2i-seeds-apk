import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import 'add_customer_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

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
        return DateTimeRange(
            start: now.subtract(Duration(days: now.weekday - 1)), end: now);
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
        // Add customer button
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
                      size: 48, color: AppColors.border),
                  const SizedBox(height: 12),
                  const Text('कोई ग्राहक नहीं',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AddCustomerScreen()),
                    ).then((_) => _load()),
                    child: const Text('+ नया ग्राहक जोड़ें'),
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
    final hasCredit      = customer.outstanding < 0; // advance deposit / overpayment
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
                  : hasCredit
                      ? const Color(0xFFBBF7D0)
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
                  : hasCredit
                      ? AppColors.successLight
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
                        : hasCredit
                            ? AppColors.success
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
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: bills.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.border),
                itemBuilder: (_, i) => _billRow(bills[i]),
              ),
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

  Widget _billRow(Bill bill) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bill.isCredit ? AppColors.dangerLight : AppColors.successLight,
        ),
        child: Icon(
          bill.isCredit
              ? Icons.credit_card_outlined
              : Icons.payments_outlined,
          size: 18,
          color: bill.isCredit ? AppColors.danger : AppColors.success,
        ),
      ),
      title: Text(bill.customerName ?? 'नकद ग्राहक',
          style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 13),
          overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${DateFormat('dd MMM hh:mm a').format(bill.createdAt)} · ${bill.billDetails.length} आइटम',
        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(_fmt(bill.totalAmount),
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 14,
                  color: bill.isCredit ? AppColors.danger : AppColors.success)),
          Text(bill.isCredit ? 'उधार' : 'नकद',
              style: TextStyle(
                  fontSize: 10,
                  color: bill.isCredit ? AppColors.danger : AppColors.success)),
        ],
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
  List<Map<String, dynamic>> _ledger = []; // ascending order (oldest → newest)
  List<double> _runningBalances = [];       // running balance AFTER each entry

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await SupabaseService.fetchCustomerLedger(widget.customer.name);
      _ledger = data;
      _computeRunningBalances();
    } finally {
      setState(() => _loading = false);
    }
  }

  void _computeRunningBalances() {
    double balance = widget.customer.openingBalance;
    _runningBalances = [];
    for (final entry in _ledger) {
      final type  = entry['type']         as String? ?? '';
      final amt   = (entry['amount']       as num?)?.toDouble() ?? 0;
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
          break; // no outstanding impact
      }
      _runningBalances.add(balance);
    }
  }

  // Negative = customer has a credit balance (advance deposit / overpayment)
  double get _outstanding =>
      _runningBalances.isEmpty ? widget.customer.openingBalance : _runningBalances.last;

  double get _totalCreditGiven => _ledger.fold<double>(0, (s, e) {
    final type  = e['type']         as String? ?? '';
    final amt   = (e['amount']       as num?)?.toDouble() ?? 0;
    final nagad = (e['nagad_amount'] as num?)?.toDouble() ?? 0;
    if (type == 'credit') return s + amt;
    if (type == 'split')  return s + (amt - nagad).clamp(0, double.infinity);
    return s;
  });

  double get _totalReceived => _ledger.fold<double>(0, (s, e) {
    final type  = e['type']         as String? ?? '';
    final amt   = (e['amount']       as num?)?.toDouble() ?? 0;
    final nagad = (e['nagad_amount'] as num?)?.toDouble() ?? 0;
    if (type == 'payment' || type == 'deposit' || type == 'cash') return s + amt;
    if (type == 'split') return s + nagad;
    return s;
  });

  String _fmt(double n) =>
      n >= 1000 ? '₹${(n / 1000).toStringAsFixed(1)}k' : '₹${n.toStringAsFixed(0)}';

  Future<void> _showAddEntryDialog() async {
    String entryType = 'payment';
    final amtCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          bool submitting = false;
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('लेनदेन दर्ज करें',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
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
                color: const Color(0xFF7C3AED),
                bgColor: const Color(0xFFEDE9FE),
                onTap: () => setLocal(() => entryType = 'deposit'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: amtCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  prefixText: '₹  ',
                  labelText: 'राशि',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ]),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('रद्द करें',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
              StatefulBuilder(
                builder: (ctx2, setSub) => ElevatedButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          final amt = double.tryParse(amtCtrl.text);
                          if (amt == null || amt <= 0) return;
                          setSub(() => submitting = true);
                          try {
                            if (entryType == 'payment') {
                              await SupabaseService.recordPayment(
                                  customerName: widget.customer.name,
                                  amount: amt);
                            } else {
                              await SupabaseService.recordDeposit(
                                  customerName: widget.customer.name,
                                  amount: amt);
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _load();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(
                                      '₹${amt.toStringAsFixed(0)} दर्ज किया')));
                            }
                          } catch (e) {
                            setSub(() => submitting = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('त्रुटि: $e')));
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
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
              ),
            ],
          );
        },
      ),
    );
    amtCtrl.dispose();
  }

  // ── C-05: Edit customer ────────────────────────────────────────────────────
  Future<void> _showEditDialog() async {
    // Name locked if the customer has any past bills (credit / cash / split)
    final hasBills = _ledger.any(
        (e) => ['credit', 'cash', 'split'].contains(e['type'] as String?));

    final phoneCtrl   = TextEditingController(text: widget.customer.phone ?? '');
    final balCtrl     = TextEditingController(
        text: widget.customer.openingBalance.abs().toStringAsFixed(0));
    // true = debt (positive), false = advance (negative)
    bool isDebt = widget.customer.openingBalance >= 0;
    final editFormKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          bool saving = false;
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(children: [
              const Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
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
                        border: Border.all(color: AppColors.warning.withOpacity(0.4)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.lock_outline,
                            size: 14, color: AppColors.warning),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'पिछले बिल होने के कारण नाम नहीं बदला जा सकता',
                            style: TextStyle(fontSize: 11, color: AppColors.warning),
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
                        onTap: () => setLocal(() => isDebt = true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _balanceChip(
                        label: 'अग्रिम',
                        active: !isDebt,
                        color: const Color(0xFF7C3AED),
                        bgColor: const Color(0xFFEDE9FE),
                        onTap: () => setLocal(() => isDebt = false),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: balCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
              StatefulBuilder(
                builder: (ctx2, setSub) => ElevatedButton(
                  onPressed: saving ? null : () async {
                    if (!editFormKey.currentState!.validate()) return;
                    setSub(() => saving = true);
                    try {
                      final raw = double.tryParse(balCtrl.text) ?? 0;
                      final ob  = isDebt ? raw : -raw;
                      final ph  = phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
                      await SupabaseService.updateCustomer(
                        id:             widget.customer.id,
                        phone:          ph,
                        openingBalance: ob,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _load();
                    } catch (e) {
                      setSub(() => saving = false);
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
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Text('सहेजें',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          );
        },
      ),
    );
    phoneCtrl.dispose();
    balCtrl.dispose();
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
    // Hard block: cannot delete while outstanding ≠ 0
    if (_outstanding != 0) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
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
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('हटाने में त्रुटि: $e')));
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
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textMuted)),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final outstanding = _outstanding;
    final isCredit    = outstanding < 0;
    final isClear     = outstanding == 0;
    final balLabel = isCredit ? 'क्रेडिट बैलेंस' : (isClear ? 'चुकता' : 'कुल बकाया');

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
                      backgroundColor: Colors.white.withOpacity(0.2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(widget.customer.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16),
                          overflow: TextOverflow.ellipsis),
                      const Text('ग्राहक खाता',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 11)),
                    ]),
                  ),
                  // + दर्ज करें
                  GestureDetector(
                    onTap: _showAddEntryDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.3)),
                      ),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text('दर्ज करें',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // C-05 / C-06: edit & delete menu
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    onSelected: (v) {
                      if (v == 'edit')   _showEditDialog();
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
                const SizedBox(height: 16),

                // 3-tile summary card
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: _hStat('उधार दिया',
                          _loading ? '—' : _fmt(_totalCreditGiven)),
                    ),
                    Container(
                        height: 30,
                        width: 1,
                        color: Colors.white.withOpacity(0.2)),
                    Expanded(
                      child: _hStat('नकद मिला',
                          _loading ? '—' : _fmt(_totalReceived)),
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
          const Expanded(
              child: Center(child: CircularProgressIndicator()))
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
                                  fontSize: 10,
                                  color: AppColors.textMuted)),
                        ]),
                      ),
                      if (_ledger.isEmpty &&
                          widget.customer.openingBalance == 0)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                            child: Text('कोई लेनदेन नहीं',
                                style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 13)),
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
                          separatorBuilder: (_, __) => const Divider(
                              height: 1, color: AppColors.border),
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
                  const SizedBox(height: 24),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _hStat(String label, String value,
      {bool highlight = false, bool isGreen = false}) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(value,
          style: TextStyle(
              color: highlight
                  ? (isGreen ? const Color(0xFF4ADE80) : Colors.white)
                  : Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: highlight ? 16 : 14,
              letterSpacing: -0.5)),
      const SizedBox(height: 3),
      Text(label,
          style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 9,
              fontWeight: FontWeight.w500),
          textAlign: TextAlign.center),
    ]);
  }

  Widget _openingBalanceRow() {
    final ob       = widget.customer.openingBalance;
    final isDebt   = ob > 0;   // customer owes us
    final isAdv    = ob < 0;   // customer pre-paid (advance)
    final color    = isDebt  ? AppColors.danger : const Color(0xFF7C3AED);
    final bgColor  = isDebt  ? AppColors.dangerLight : const Color(0xFFEDE9FE);
    final icon     = isAdv   ? Icons.savings_outlined
                             : Icons.account_balance_wallet_outlined;
    final sign     = isDebt  ? '+' : '-';
    final label    = isDebt  ? 'शुरुआती बकाया' : 'शुरुआती अग्रिम';
    final sublabel = isDebt  ? 'Opening Debt Balance' : 'Advance Pre-payment';
    final balLabel = isDebt  ? 'उधार' : 'अग्रिम';

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
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
          Text(balLabel,
              style: TextStyle(fontSize: 9, color: color)),
        ],
      ),
    );
  }

  Widget _ledgerRow(Map<String, dynamic> entry, double runningBalance) {
    final type  = entry['type']         as String? ?? '';
    final amt   = (entry['amount']       as num?)?.toDouble() ?? 0;
    final nagad = (entry['nagad_amount'] as num?)?.toDouble() ?? 0;
    final date  = entry['created_at'] != null
        ? DateTime.tryParse(entry['created_at'] as String)
        : null;

    Color    rowColor;
    IconData rowIcon;
    String   rowLabel;
    String   amtText;

    switch (type) {
      case 'split':
        rowColor = Colors.orange.shade700;
        rowIcon  = Icons.call_split;
        rowLabel = 'आंशिक नकद+उधार';
        final udhar = (amt - nagad).clamp(0, double.infinity);
        amtText = '₹${nagad.toStringAsFixed(0)} नकद · ₹${udhar.toStringAsFixed(0)} उधार';
        break;
      case 'payment':
        rowColor = AppColors.success;
        rowIcon  = Icons.arrow_downward;
        rowLabel = 'भुगतान मिला';
        amtText  = '-₹${amt.toStringAsFixed(0)}';
        break;
      case 'deposit':
        rowColor = const Color(0xFF7C3AED);
        rowIcon  = Icons.savings_outlined;
        rowLabel = 'अग्रिम जमा';
        amtText  = '-₹${amt.toStringAsFixed(0)}';
        break;
      case 'cash':
        rowColor = AppColors.success;
        rowIcon  = Icons.payments_outlined;
        rowLabel = 'नकद बिक्री';
        amtText  = '₹${amt.toStringAsFixed(0)}';
        break;
      default: // 'credit'
        rowColor = AppColors.danger;
        rowIcon  = Icons.arrow_upward;
        rowLabel = 'उधार';
        amtText  = '+₹${amt.toStringAsFixed(0)}';
    }

    // Running balance annotation per row
    final balIsCredit = runningBalance < 0;
    final balColor    = balIsCredit
        ? AppColors.success
        : (runningBalance > 0 ? AppColors.danger : AppColors.success);
    final balText     = balIsCredit
        ? 'क्रेडिट ${_fmt(runningBalance.abs())}'
        : (runningBalance > 0
            ? 'बकाया ${_fmt(runningBalance)}'
            : 'चुकता ✓');

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: rowColor),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Text(amtText,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: rowColor)),
        ],
      ),
      subtitle: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            date != null
                ? DateFormat('dd MMM, hh:mm a').format(date.toLocal())
                : '—',
            style: const TextStyle(
                fontSize: 11, color: AppColors.textMuted),
          ),
          Text(balText,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: balColor)),
        ],
      ),
    );
  }
}
