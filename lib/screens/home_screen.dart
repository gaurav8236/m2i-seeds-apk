import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import '../widgets/bill_card.dart';
import 'past_bills_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int) onTabChange;
  final void Function(VoidCallback) onRegisterReload;
  const HomeScreen({super.key, required this.onTabChange, required this.onRegisterReload});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  double _credit = 0, _paid = 0, _outstanding = 0;
  int _lowStockCount = 0;
  List<Bill> _recentBills = [];
  StatsPeriod _period = StatsPeriod.thisMonth;
  String? _avatarUrl;
  String? _displayName;

  @override
  void initState() {
    super.initState();
    widget.onRegisterReload(_load);
    _load();
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
        return DateTimeRange(
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
        SupabaseService.fetchStock(),
        SupabaseService.fetchPastBills(),
        AuthService.fetchProfile(),
      ]);
      final stats = results[0] as Map<String, double>;
      final outstanding = results[1] as double;
      final stock = results[2] as List<StockItem>;
      final bills = results[3] as List<Bill>;
      final profile = results[4] as Map<String, String?>;
      setState(() {
        _credit = stats['credit'] ?? 0;
        _paid = stats['paid'] ?? 0;
        _outstanding = outstanding;
        _lowStockCount = stock.where((s) => s.isLow).length;
        _recentBills = bills.take(4).toList();
        _avatarUrl = profile['photo_url'];
        _displayName = profile['display_name'] ?? profile['google_name'];
      });
    } catch (e) {
      debugPrint('Home load error: $e');
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
      setState(() => _period = StatsPeriod.custom);
      setState(() => _loading = true);
      try {
        final stats = await SupabaseService.fetchFilteredStats(
            from: picked.start, to: picked.end);
        setState(() {
          _credit = stats['credit'] ?? 0;
          _paid = stats['paid'] ?? 0;
        });
      } finally {
        setState(() => _loading = false);
      }
    }
  }

  String _fmt(double n) =>
      n >= 1000 ? '₹${(n / 1000).toStringAsFixed(1)}k' : '₹${n.toStringAsFixed(0)}';


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
                        // Brand row with avatar
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('SmartDukan',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                                Text('दुकानदार सहायक',
                                    style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 11)),
                              ],
                            ),
                            GestureDetector(
                              onTap: () => Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => const ProfileScreen()))
                                  .then((_) => _load()),
                              child: _buildAvatar(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Period filter chips
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _periodChip('आज', StatsPeriod.today),
                              const SizedBox(width: 8),
                              _periodChip('यह हफ़्ता', StatsPeriod.thisWeek),
                              const SizedBox(width: 8),
                              _periodChip('यह महीना', StatsPeriod.thisMonth),
                              const SizedBox(width: 8),
                              _customChip(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Stats row — only उधार दिया + नकद जमा (period-filtered)
                        Container(
                          padding: const EdgeInsets.only(top: 14),
                          decoration: BoxDecoration(
                            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.18))),
                          ),
                          child: Row(
                            children: [
                              _statCell('उधार दिया', _credit),
                              _divider(),
                              _statCell('नकद जमा', _paid),
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
                  if (!_loading && _lowStockCount > 0) ...[
                    _lowStockBanner(),
                    const SizedBox(height: 12),
                  ],

                  // ── बकाया card (always-current, not period-filtered) ──
                  if (!_loading && _outstanding > 0) ...[
                    _bakayaCard(),
                    const SizedBox(height: 12),
                  ],

                  // ── New Bill CTA ─────────────────────────────────────
                  _newBillCTA(context),
                  const SizedBox(height: 10),

                  // ── Secondary actions ────────────────────────────────
                  Row(
                    children: [
                      Expanded(child: _actionCard(context, Icons.inventory_2_outlined, 'स्टॉक', 'प्रबंधन करें', 2)),
                      const SizedBox(width: 10),
                      Expanded(child: _actionCard(context, Icons.menu_book_outlined, 'ग्राहक खाता', 'बकाया देखें', 3)),
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

  Widget _buildAvatar() {
    final initials = (_displayName ?? 'U')
        .trim()
        .split(' ')
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();
    return Container(
      width: 38, height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.2),
        border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
        image: _avatarUrl != null
            ? DecorationImage(image: NetworkImage(_avatarUrl!), fit: BoxFit.cover)
            : null,
      ),
      child: _avatarUrl == null
          ? Center(
              child: Text(initials,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)))
          : null,
    );
  }

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
          border: Border.all(color: Colors.white.withOpacity(active ? 0 : 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600,
            color: active ? AppColors.primary : Colors.white,
          ),
        ),
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
          border: Border.all(color: Colors.white.withOpacity(active ? 0 : 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.date_range, size: 12,
              color: active ? AppColors.primary : Colors.white),
          const SizedBox(width: 4),
          Text('कस्टम',
              style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: active ? AppColors.primary : Colors.white,
              )),
        ]),
      ),
    );
  }

  Widget _statCell(String label, double value) {
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
              style: TextStyle(
                  color: Colors.white.withOpacity(0.82), fontSize: 10, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        height: 36, width: 1,
        color: Colors.white.withOpacity(0.18),
        margin: const EdgeInsets.symmetric(horizontal: 8),
      );

  Widget _bakayaCard() {
    return GestureDetector(
      onTap: () => widget.onTabChange(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFCACA)),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.dangerLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.account_balance_wallet_outlined,
                  color: AppColors.danger, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('कुल बकाया उधार',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: AppColors.danger)),
                Text(
                  _loading ? '—' : _fmt(_outstanding),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                      color: AppColors.danger, letterSpacing: -0.5),
                ),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('देखें',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lowStockBanner() {
    return GestureDetector(
      onTap: () => widget.onTabChange(2),
      child: Container(
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
                  Text('बोलकर बिल — हिंदी या अंग्रेज़ी',
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
    return Column(
      children: _recentBills.map((bill) => BillCard(bill: bill)).toList(),
    );
  }
}
