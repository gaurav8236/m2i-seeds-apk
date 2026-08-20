import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/supabase_service.dart';
import '../theme.dart';

class AddCustomerScreen extends StatefulWidget {
  const AddCustomerScreen({super.key});

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  final _formKey  = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _balanceCtrl  = TextEditingController();
  bool _saving  = false;
  bool _isDirty = false;

  /// C-01: opening-balance direction toggle.
  /// true  = customer owes US  → stored as +openingBalance
  /// false = customer pre-paid → stored as -openingBalance
  bool _isDebt = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      // Sign: debt = positive, advance pre-payment = negative
      final rawBalance    = double.tryParse(_balanceCtrl.text) ?? 0;
      final openingBalance = _isDebt ? rawBalance : -rawBalance;

      // Store only digits for phone
      final phone = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');

      await SupabaseService.createCustomer(
        name:           _nameCtrl.text.trim(),
        phone:          phone.isEmpty ? null : phone,
        openingBalance: openingBalance,
      );
      setState(() => _isDirty = false);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('त्रुटि: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleBack() async {
    if (!_isDirty) { Navigator.pop(context); return; }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('बदलाव छोड़ें?'),
        content: const Text('सहेजे बिना जाने पर बदलाव खो जाएंगे।'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('रहने दें'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('छोड़ें',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if ((leave ?? false) && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Column(children: [
          // ── Header ─────────────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: primaryGradient,
              borderRadius: const BorderRadius.only(
                bottomLeft:  Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Row(children: [
                  IconButton(
                    onPressed: _handleBack,
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('नया ग्राहक',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                    Text('Add New Customer',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ]),
                ]),
              ),
            ),
          ),

          // ── Form ───────────────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                // V-01 / UX-02: show errors as the user types, not only on submit
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                    // ── Name ─────────────────────────────────────────────────
                    _lbl('ग्राहक का नाम *'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      // UX-01: block digits and decimal points at input level
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'[0-9.]')),
                      ],
                      decoration: const InputDecoration(
                        hintText: 'जैसे: Ramesh Kumar',
                        prefixIcon: Icon(Icons.person_outline, size: 18),
                      ),
                      onChanged: (_) => setState(() => _isDirty = true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'नाम ज़रूरी है';
                        if (RegExp(r'[0-9]').hasMatch(v)) return 'नाम में अंक नहीं होने चाहिए';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // ── Phone ────────────────────────────────────────────────
                    _lbl('मोबाइल नंबर (वैकल्पिक)'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      // Accept digits only; limit to 10
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      decoration: const InputDecoration(
                        hintText: '9876543210',
                        prefixIcon: Icon(Icons.phone_outlined, size: 18),
                        counterText: '',
                      ),
                      onChanged: (_) => setState(() => _isDirty = true),
                      validator: (v) {
                        if (v == null || v.isEmpty) return null; // optional
                        final digits = v.replaceAll(RegExp(r'\D'), '');
                        if (digits.length != 10) return '10 अंकों का नंबर डालें';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // ── Opening balance (C-01) ────────────────────────────────
                    _lbl('शुरुआती बैलेंस (वैकल्पिक)'),
                    const SizedBox(height: 8),

                    // Type toggle: उधार / अग्रिम
                    Row(children: [
                      Expanded(
                        child: _balanceTypeChip(
                          label: 'उधार',
                          sub:   'ग्राहक हम पर बकाया है',
                          icon:  Icons.arrow_upward,
                          active: _isDebt,
                          color:  AppColors.danger,
                          bgColor: AppColors.dangerLight,
                          onTap: () => setState(() { _isDebt = true; _isDirty = true; }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _balanceTypeChip(
                          label: 'अग्रिम',
                          sub:   'ग्राहक ने पहले से दिया',
                          icon:  Icons.savings_outlined,
                          active: !_isDebt,
                          color:  const Color(0xFF7C3AED),
                          bgColor: const Color(0xFFEDE9FE),
                          onTap: () => setState(() { _isDebt = false; _isDirty = true; }),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),

                    TextFormField(
                      controller: _balanceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                      ],
                      decoration: InputDecoration(
                        hintText: '0',
                        prefixText: '₹ ',
                        prefixIcon: Icon(
                          _isDebt ? Icons.account_balance_wallet_outlined
                                  : Icons.savings_outlined,
                          size: 18,
                          color: _isDebt ? AppColors.danger : const Color(0xFF7C3AED),
                        ),
                      ),
                      onChanged: (_) => setState(() => _isDirty = true),
                      validator: (v) {
                        if (v == null || v.isEmpty) return null;
                        if (double.tryParse(v) == null) return 'सही राशि डालें';
                        if ((double.tryParse(v) ?? 0) < 0) return 'राशि 0 या अधिक होनी चाहिए';
                        return null;
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isDebt
                          ? 'उधार: ग्राहक पर पहले से बकाया राशि (शुरुआती देनदारी)'
                          : 'अग्रिम: ग्राहक ने पहले से पैसे जमा किए हैं',
                      style: TextStyle(
                          fontSize: 11,
                          color: _isDebt ? AppColors.danger : const Color(0xFF7C3AED),
                          fontStyle: FontStyle.italic),
                    ),

                    const SizedBox(height: 24),

                    // ── Save button ───────────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5))
                            : const Icon(Icons.check, size: 18),
                        label: Text(_saving ? 'सहेज रहे हैं...' : 'ग्राहक जोड़ें',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // Balance type selector chip
  Widget _balanceTypeChip({
    required String label,
    required String sub,
    required IconData icon,
    required bool active,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: active ? bgColor : AppColors.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: active ? color : AppColors.border,
              width: active ? 1.5 : 1),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: active ? color : AppColors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: active ? color : AppColors.textPrimary)),
              Text(sub,
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _lbl(String t) => Text(t,
      style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary));
}
