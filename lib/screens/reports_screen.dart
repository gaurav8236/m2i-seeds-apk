import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../theme.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;

  // Ledger state
  List<String> _customerNames = [];
  String? _selectedCustomer;
  List<Map<String, dynamic>> _ledger = [];
  bool _ledgerLoading = false;
  final _customerCtrl = TextEditingController();
  bool _showSuggestions = false;

  // Payment recording
  final _payCtrl = TextEditingController();
  bool _paying = false;

  // Month stats
  double _credit = 0, _paid = 0;
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
    _customerCtrl.dispose();
    _payCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stats = await SupabaseService.fetchMonthStats();
      final names = await SupabaseService.fetchCustomerNames();
      final bills = await SupabaseService.fetchPastBills();
      setState(() {
        _credit = stats['credit'] ?? 0;
        _paid = stats['paid'] ?? 0;
        _customerNames = names;
        _allBills = bills;
      });
    } catch (e) {
      _showSnack('लोड नहीं हो सका: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadLedger(String name) async {
    setState(() { _ledgerLoading = true; _ledger = []; });
    try {
      final data = await SupabaseService.fetchCustomerLedger(name);
      setState(() => _ledger = data);
    } catch (e) {
      _showSnack('खाता लोड नहीं हो सका: $e');
    } finally {
      setState(() => _ledgerLoading = false);
    }
  }

  Future<void> _recordPayment() async {
    final amt = double.tryParse(_payCtrl.text);
    if (amt == null || amt <= 0 || _selectedCustomer == null) return;
    setState(() => _paying = true);
    try {
      await SupabaseService.recordPayment(customerName: _selectedCustomer!, amount: amt);
      _payCtrl.clear();
      await _loadLedger(_selectedCustomer!);
      await _load();
      _showSnack('₹${amt.toStringAsFixed(0)} दर्ज किया गया');
    } catch (e) {
      _showSnack('त्रुटि: $e');
    } finally {
      setState(() => _paying = false);
    }
  }

  double get _outstanding {
    if (_ledger.isEmpty) return 0;
    return _ledger.fold<double>(0, (s, e) {
      final type = e['type'] as String? ?? '';
      final amt = (e['amount'] as num?)?.toDouble() ?? 0;
      if (type == 'credit') return s + amt;
      if (type == 'payment') return s - amt;
      return s;
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
                      Text('खाता-बही', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                      Text('Ledger & Reports', style: TextStyle(color: Colors.white70, fontSize: 10)),
                    ]),
                  ]),
                  const SizedBox(height: 14),
                  // Stats
                  Row(children: [
                    Expanded(child: _headerStat('उधार दिया', _fmt(_credit))),
                    _vDivider(),
                    Expanded(child: _headerStat('नकद जमा', _fmt(_paid))),
                    _vDivider(),
                    Expanded(child: _headerStat('बकाया', _fmt(_credit))),
                  ]),
                  const SizedBox(height: 12),
                  TabBar(
                    controller: _tabController,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    indicatorColor: Colors.white,
                    indicatorWeight: 2.5,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
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
              children: [
                _ledgerTab(),
                _reportsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerStat(String label, String value) {
    return Column(children: [
      Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.5)),
      const SizedBox(height: 3),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500)),
    ]);
  }

  Widget _vDivider() => Container(
        height: 32, width: 1, color: Colors.white.withOpacity(0.2),
        margin: const EdgeInsets.symmetric(horizontal: 8));

  // ── LEDGER TAB ─────────────────────────────────────────────────────────────

  Widget _ledgerTab() {
    final suggestions = _customerNames
        .where((n) => n.toLowerCase().contains(_customerCtrl.text.toLowerCase()))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Customer search
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('ग्राहक चुनें', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              TextField(
                controller: _customerCtrl,
                decoration: const InputDecoration(
                  hintText: 'नाम खोजें...',
                  prefixIcon: Icon(Icons.person_search, size: 18),
                  isDense: true,
                ),
                onChanged: (v) => setState(() {
                  _showSuggestions = v.isNotEmpty;
                  if (_selectedCustomer != null && v != _selectedCustomer) {
                    _selectedCustomer = null;
                    _ledger = [];
                  }
                }),
              ),
              if (_showSuggestions && suggestions.isNotEmpty)
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
                      leading: const CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.primaryLight,
                        child: Icon(Icons.person, size: 14, color: AppColors.primary),
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      onTap: () {
                        _customerCtrl.text = name;
                        setState(() {
                          _selectedCustomer = name;
                          _showSuggestions = false;
                        });
                        _loadLedger(name);
                      },
                    )).toList(),
                  ),
                ),
            ]),
          ),

          if (_selectedCustomer != null) ...[
            const SizedBox(height: 14),

            // Outstanding + payment
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _outstanding > 0 ? const Color(0xFFFDE68A) : AppColors.border,
                  width: _outstanding > 0 ? 1.5 : 1,
                ),
              ),
              child: Column(children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_selectedCustomer!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text('बकाया', style: TextStyle(fontSize: 11, color: _outstanding > 0 ? AppColors.danger : AppColors.success)),
                    ]),
                    Text(
                      '₹${_outstanding.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -1,
                        color: _outstanding > 0 ? AppColors.danger : AppColors.success,
                      ),
                    ),
                  ],
                ),
                if (_outstanding > 0) ...[
                  const Divider(height: 20),
                  const Text('भुगतान दर्ज करें', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.4)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _payCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(prefixText: '₹', hintText: 'राशि', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _paying ? null : _recordPayment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _paying
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : const Text('दर्ज', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ],
              ]),
            ),

            const SizedBox(height: 14),

            // Transaction list
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: Row(children: [
                    Text('लेनदेन इतिहास', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.5)),
                  ]),
                ),
                if (_ledgerLoading)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_ledger.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: Text('कोई लेनदेन नहीं', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _ledger.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (_, i) => _ledgerRow(_ledger[i]),
                  ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _ledgerRow(Map<String, dynamic> entry) {
    final type = entry['type'] as String? ?? '';
    final amt = (entry['amount'] as num?)?.toDouble() ?? 0;
    final date = entry['created_at'] != null
        ? DateTime.tryParse(entry['created_at'] as String) : null;
    final isCredit = type == 'credit';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
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
            color: isCredit ? AppColors.danger : AppColors.success,
          )),
      subtitle: date != null
          ? Text(DateFormat('dd MMM, hh:mm a').format(date),
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted))
          : null,
      trailing: Text(
        '${isCredit ? '+' : '-'}₹${amt.toStringAsFixed(0)}',
        style: TextStyle(
          fontWeight: FontWeight.w800, fontSize: 15,
          color: isCredit ? AppColors.danger : AppColors.success,
        ),
      ),
    );
  }

  // ── REPORTS TAB ─────────────────────────────────────────────────────────────

  Widget _reportsTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final creditBills = _allBills.where((b) => b.isCredit).toList();
    final cashBills = _allBills.where((b) => !b.isCredit).toList();
    final creditTotal = creditBills.fold(0.0, (s, b) => s + b.totalAmount);
    final cashTotal = cashBills.fold(0.0, (s, b) => s + b.totalAmount);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // Summary cards
          Row(children: [
            Expanded(child: _summaryCard('नकद बिक्री', cashTotal, cashBills.length, AppColors.success, AppColors.successLight, Icons.payments_outlined)),
            const SizedBox(width: 10),
            Expanded(child: _summaryCard('उधार बिक्री', creditTotal, creditBills.length, AppColors.danger, AppColors.dangerLight, Icons.credit_card_outlined)),
          ]),
          const SizedBox(height: 10),
          _summaryCard('कुल बिक्री', cashTotal + creditTotal, _allBills.length, AppColors.primary, AppColors.primaryLight, Icons.receipt_long_outlined, wide: true),
          const SizedBox(height: 20),

          // Recent bills grouped by date
          const Text('बिल इतिहास', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          if (_allBills.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('कोई बिल नहीं', style: TextStyle(color: AppColors.textMuted)),
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
                itemCount: _allBills.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                itemBuilder: (_, i) => _billRow(_allBills[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, double amount, int count, Color color, Color bgColor, IconData icon, {bool wide = false}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: wide
          ? Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                  Text(_fmt(amount), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: color, letterSpacing: -0.5)),
                  Text('$count बिल', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ]),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(height: 10),
                Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(_fmt(amount), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: color, letterSpacing: -0.5)),
                Text('$count बिल', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
    );
  }

  Widget _billRow(Bill bill) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bill.isCredit ? AppColors.dangerLight : AppColors.successLight,
        ),
        child: Icon(
          bill.isCredit ? Icons.credit_card_outlined : Icons.payments_outlined,
          size: 18,
          color: bill.isCredit ? AppColors.danger : AppColors.success,
        ),
      ),
      title: Text(
        bill.customerName ?? 'नकद ग्राहक',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        overflow: TextOverflow.ellipsis,
      ),
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
              style: TextStyle(fontSize: 10,
                  color: bill.isCredit ? AppColors.danger : AppColors.success)),
        ],
      ),
    );
  }
}
