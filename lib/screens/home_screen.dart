import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import 'past_bills_screen.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int) onTabChange;
  const HomeScreen({super.key, required this.onTabChange});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  double _credit = 0, _paid = 0;
  int _lowStockCount = 0;
  List<Bill> _recentBills = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stats = await SupabaseService.fetchMonthStats();
      final stock = await SupabaseService.fetchStock();
      final bills = await SupabaseService.fetchPastBills();
      setState(() {
        _credit = stats['credit'] ?? 0;
        _paid = stats['paid'] ?? 0;
        _lowStockCount = stock.where((s) => s.isLow).length;
        _recentBills = bills.take(4).toList();
      });
    } catch (e) {
      debugPrint('Home load error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  String _fmt(double n) =>
      n >= 1000 ? '₹${(n / 1000).toStringAsFixed(1)}k' : '₹${n.toStringAsFixed(0)}';

  String _fmtDate(DateTime d) =>
      DateFormat('dd MMM, hh:mm a').format(d);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            // ── Gradient Header ────────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(
                  gradient: primaryGradient,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0D47A1).withOpacity(0.28),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Brand row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.white.withOpacity(0.25)),
                                  ),
                                  child: const Icon(Icons.mic, color: Colors.white, size: 18),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('SmartDukan',
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                                    Text('दुकानदार सहायक',
                                        style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 11)),
                                  ],
                                ),
                              ],
                            ),
                            Text(
                              DateFormat('d MMM').format(DateTime.now()),
                              style: TextStyle(color: Colors.white.withOpacity(0.82), fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Stats row
                        Container(
                          padding: const EdgeInsets.only(top: 16),
                          decoration: BoxDecoration(
                            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.18))),
                          ),
                          child: Row(
                            children: [
                              _statCell('उधार दिया', _credit, true),
                              _divider(),
                              _statCell('नकद जमा', _paid, false),
                              _divider(),
                              _statCell('बकाया', _credit > 0 ? _credit : 0, false),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ── Low stock alert ──────────────────────────────────
                  if (!_loading && _lowStockCount > 0)
                    _lowStockBanner(),

                  // ── New Bill CTA ─────────────────────────────────────
                  _newBillCTA(context),
                  const SizedBox(height: 10),

                  // ── Secondary actions ────────────────────────────────
                  Row(
                    children: [
                      Expanded(child: _actionCard(context, Icons.inventory_2_outlined, 'स्टॉक', 'Inventory', 2)),
                      const SizedBox(width: 10),
                      Expanded(child: _actionCard(context, Icons.menu_book_outlined, 'ग्राहक खाता', 'Ledger', 3)),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Recent bills ─────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('हाल के बिल',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
                      GestureDetector(
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const PastBillsScreen())),
                        child: Row(
                          children: const [
                            Text('सभी देखें',
                                style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                            Icon(Icons.chevron_right, size: 16, color: AppColors.primary),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _recentBillsList(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCell(String label, double value, bool hasBorder) {
    return Expanded(
      child: Column(
        children: [
          Text(
            _loading ? '—' : _fmt(value),
            style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: -0.5),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(color: Colors.white.withOpacity(0.82), fontSize: 10, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        height: 36,
        width: 1,
        color: Colors.white.withOpacity(0.18),
        margin: const EdgeInsets.symmetric(horizontal: 8),
      );

  Widget _lowStockBanner() {
    return GestureDetector(
      onTap: () {
        // navigate to inventory tab
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.warningLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  children: [
                    TextSpan(
                      text: '$_lowStockCount सामान',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const TextSpan(text: ' का स्टॉक कम है'),
                  ],
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _newBillCTA(BuildContext context) {
    return GestureDetector(
      onTap: () => widget.onTabChange(1),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          gradient: primaryGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.25)),
              ),
              child: const Icon(Icons.mic, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('नया बिल बनाएं',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                  SizedBox(height: 2),
                  Text('बोलकर बिल — हिंदी या English',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white70, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _actionCard(BuildContext context, IconData icon, String title, String subtitle, int tabIndex) {
    return GestureDetector(
      onTap: () => widget.onTabChange(tabIndex),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
        ),
        child: Row(
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
                Text(subtitle,
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentBillsList() {
    if (_loading) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(20),
        child: CircularProgressIndicator(),
      ));
    }
    if (_recentBills.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: const Column(
          children: [
            Icon(Icons.trending_up, size: 32, color: AppColors.border),
            SizedBox(height: 8),
            Text('अभी तक कोई बिल नहीं', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: _recentBills.asMap().entries.map((entry) {
          final i = entry.key;
          final bill = entry.value;
          return Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                title: Text(
                  bill.customerName ?? 'नकद ग्राहक',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_fmtDate(bill.createdAt)} · ${bill.billDetails.length} आइटम',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _fmt(bill.totalAmount),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: bill.isCredit ? AppColors.danger : AppColors.success,
                      ),
                    ),
                    Text(
                      bill.isCredit ? 'उधार' : 'नकद',
                      style: TextStyle(
                        fontSize: 10,
                        color: bill.isCredit ? AppColors.danger : AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
              if (i < _recentBills.length - 1)
                Divider(height: 1, color: AppColors.bg),
            ],
          );
        }).toList(),
      ),
    );
  }
}
