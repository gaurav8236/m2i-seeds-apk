import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';
import '../theme.dart';
import '../widgets/bill_card.dart';

class PastBillsScreen extends StatefulWidget {
  const PastBillsScreen({super.key});

  @override
  State<PastBillsScreen> createState() => _PastBillsScreenState();
}

class _PastBillsScreenState extends State<PastBillsScreen> {
  List<Bill> _bills = [];
  bool _loading = true;
  String _search = '';
  BillTypeFilter _filter = BillTypeFilter.all;

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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('लोड नहीं हो सका: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Bill> get _filtered {
    return _bills.where((b) {
      final q = _search.toLowerCase();
      final nameMatch = (b.customerName ?? '').toLowerCase().contains(q) || q.isEmpty;
      return nameMatch && _filter.matches(b);
    }).toList();
  }

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
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    if (Navigator.canPop(context)) const SizedBox(width: 10),
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
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
              BillFilterChips(
                selected: _filter,
                onChanged: (f) => setState(() => _filter = f),
              ),
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
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) => BillCard(bill: _filtered[i]),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
