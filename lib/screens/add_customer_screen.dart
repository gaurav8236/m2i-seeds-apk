import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../theme.dart';

class AddCustomerScreen extends StatefulWidget {
  const AddCustomerScreen({super.key});

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();
  bool _saving = false;

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
      await SupabaseService.createCustomer(
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        openingBalance: double.tryParse(_balanceCtrl.text) ?? 0,
      );
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
              child: Row(children: [
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
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('नया ग्राहक',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                  Text('ग्राहक की जानकारी भरें',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                ]),
              ]),
            ),
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Name
                  _lbl('ग्राहक का नाम *'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'जैसे: रमेश कुमार',
                      prefixIcon: Icon(Icons.person_outline, size: 18),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'नाम ज़रूरी है' : null,
                  ),
                  const SizedBox(height: 16),

                  // Phone
                  _lbl('मोबाइल नंबर (वैकल्पिक)'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      hintText: '9876543210',
                      prefixIcon: Icon(Icons.phone_outlined, size: 18),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return null;
                      if (v.length < 10) return 'सही नंबर डालें';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Opening balance
                  _lbl('पहले से बकाया (वैकल्पिक)'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _balanceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: '0',
                      prefixText: '₹ ',
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined,
                          size: 18),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'यदि ग्राहक पर पहले से कुछ बकाया है तो यहाँ डालें',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textMuted,
                        fontStyle: FontStyle.italic),
                  ),

                  const SizedBox(height: 24),

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
    );
  }

  Widget _lbl(String t) => Text(t,
      style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700,
          color: AppColors.textSecondary));
}
