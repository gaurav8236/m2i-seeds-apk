import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _steps = [
    _OnboardingStep(
      icon: Icons.mic,
      color: Color(0xFF1A56DB),
      bgColor: Color(0xFFE8F0FE),
      title: 'बोलकर बिल बनाएं',
      subtitle: 'हिंदी या अंग्रेज़ी में बोलें — AI खुद आइटम पहचान लेगा',
      hint: '"आलू दो किलो, मैगी एक"',
    ),
    _OnboardingStep(
      icon: Icons.inventory_2_outlined,
      color: Color(0xFF16A34A),
      bgColor: Color(0xFFF0FDF4),
      title: 'स्टॉक हमेशा अप-टू-डेट',
      subtitle: 'हर बिक्री के बाद स्टॉक खुद घटता है — कोई मेहनत नहीं',
      hint: 'कम स्टॉक की चेतावनी भी मिलेगी',
    ),
    _OnboardingStep(
      icon: Icons.account_balance_wallet_outlined,
      color: Color(0xFFDC2626),
      bgColor: Color(0xFFFEF2F2),
      title: 'उधार का हिसाब',
      subtitle: 'हर ग्राहक का बकाया एक जगह — कब दिया, कब मिला सब दर्ज',
      hint: 'भुगतान मिलने पर तुरंत दर्ज करें',
    ),
  ];

  Future<void> _finish() async {
    try {
      await AuthService.markOnboardingComplete();
    } catch (_) {}
    widget.onDone();
  }

  void _next() {
    if (_page < _steps.length - 1) {
      _controller.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _finish();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          // Skip
          Align(
            alignment: Alignment.topRight,
            child: TextButton(
              onPressed: _finish,
              child: const Text('छोड़ें',
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
            ),
          ),

          // Pages
          Expanded(
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (i) => setState(() => _page = i),
              itemCount: _steps.length,
              itemBuilder: (_, i) => _StepPage(step: _steps[i]),
            ),
          ),

          // Dots + button
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Column(children: [
              // Page dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_steps.length, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: i == _page ? 24 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == _page ? AppColors.primary : AppColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                )),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    _page < _steps.length - 1 ? 'आगे →' : 'शुरू करें',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _StepPage extends StatelessWidget {
  final _OnboardingStep step;
  const _StepPage({required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              color: step.bgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(step.icon, color: step.color, size: 48),
          ),
          const SizedBox(height: 36),
          Text(
            step.title,
            style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.w800,
                color: AppColors.textPrimary, height: 1.2),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Text(
            step.subtitle,
            style: const TextStyle(
                fontSize: 16, color: AppColors.textSecondary, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: step.bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              step.hint,
              style: TextStyle(
                  fontSize: 13, color: step.color,
                  fontStyle: FontStyle.italic, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingStep {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String title;
  final String subtitle;
  final String hint;

  const _OnboardingStep({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.title,
    required this.subtitle,
    required this.hint,
  });
}
