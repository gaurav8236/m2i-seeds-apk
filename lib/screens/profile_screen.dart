import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _avatarUrl;
  String? _email;
  final _nameCtrl = TextEditingController();
  final _shopCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _shopCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await AuthService.fetchProfile();
    if (!mounted) return;
    setState(() {
      _avatarUrl = profile['photo_url'];
      _email = profile['email'];
      _nameCtrl.text = profile['display_name'] ?? profile['google_name'] ?? '';
      _shopCtrl.text = profile['shop_name'] ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AuthService.updateProfile(
        displayName: _nameCtrl.text.trim(),
        shopName: _shopCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('प्रोफ़ाइल सहेज दी गई')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('त्रुटि: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('लॉग आउट करें?'),
        content: const Text('क्या आप वाकई लॉग आउट करना चाहते हैं?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('नहीं')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('हाँ, लॉग आउट',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) await AuthService.signOut();
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(children: [
                Row(children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('प्रोफ़ाइल', style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                    Text('आपकी दुकान की जानकारी', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ]),
                ]),
                const SizedBox(height: 20),
                // Avatar
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.2),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
                    image: _avatarUrl != null
                        ? DecorationImage(
                            image: NetworkImage(_avatarUrl!), fit: BoxFit.cover)
                        : null,
                  ),
                  child: _avatarUrl == null
                      ? Center(
                          child: Text(
                            (_nameCtrl.text.trim().isNotEmpty
                                    ? _nameCtrl.text.trim()
                                    : 'U')
                                .split(' ')
                                .take(2)
                                .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
                                .join(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 24),
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 8),
                if (_email != null)
                  Text(_email!,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
              ]),
            ),
          ),
        ),

        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                // Editable fields
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _lbl('दुकानदार का नाम'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                          hintText: 'आपका नाम', isDense: true),
                    ),
                    const SizedBox(height: 16),
                    _lbl('दुकान का नाम'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _shopCtrl,
                      decoration: const InputDecoration(
                          hintText: 'उदा. राम किराना स्टोर', isDense: true),
                    ),
                    const SizedBox(height: 16),
                    _lbl('फ़ोन / ईमेल'),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(_email ?? '—',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 14)),
                    ),
                    const SizedBox(height: 4),
                    const Text('Google से लॉगिन — बदला नहीं जा सकता',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ]),
                ),
                const SizedBox(height: 16),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _saving
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : const Text('सहेजें',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 24),

                // Logout
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout, size: 18, color: AppColors.danger),
                    label: const Text('लॉग आउट करें',
                        style: TextStyle(fontWeight: FontWeight.w600,
                            color: AppColors.danger, fontSize: 15)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.danger),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _lbl(String t) => Text(t,
      style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary));
}
