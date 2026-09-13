import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../main.dart' show SmartDukanApp;
import '../../l10n/generated/app_localizations.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// Segmented Hindi/English toggle for the app-wide language.
///
/// Stateless — it reads the current locale from `Localizations.localeOf`
/// and delegates the actual change to [SmartDukanApp.setLocale], which
/// owns the real app-level state (and persists it via `LocaleService`).
/// This widget doesn't need — and shouldn't duplicate — that state itself.
class LanguageSwitcher extends StatelessWidget {
  const LanguageSwitcher({super.key});

  Widget _segment(BuildContext context, Locale locale, String label, Locale current) {
    final active = current.languageCode == locale.languageCode;
    return Expanded(
      child: GestureDetector(
        onTap: active ? null : () => SmartDukanApp.setLocale(context, locale),
        child: Container(
          height: AppSpacing.minTouchTarget,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            label,
            style: AppTypography.bodyStrong.copyWith(
              color: active ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = Localizations.localeOf(context);
    final t = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _segment(context, const Locale('hi'), t.languageHindi, current),
          _segment(context, const Locale('en'), t.languageEnglish, current),
        ],
      ),
    );
  }
}
