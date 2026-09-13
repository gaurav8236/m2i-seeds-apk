import 'package:flutter/material.dart';
import '../../theme.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

enum AppStatusTone { success, danger, warning, info, neutral }

/// Small colored pill for a single status word (paid / due / low stock /
/// advance) — reuses the same semantic colors used everywhere else
/// (`AppColors.success`/`danger`/`warning`/`advanceViolet`) so a color
/// always means the same thing across the app.
class StatusBadge extends StatelessWidget {
  final String label;
  final AppStatusTone tone;

  const StatusBadge({super.key, required this.label, this.tone = AppStatusTone.neutral});

  Color get _bg {
    switch (tone) {
      case AppStatusTone.success:
        return AppColors.successLight;
      case AppStatusTone.danger:
        return AppColors.dangerLight;
      case AppStatusTone.warning:
        return AppColors.warningLight;
      case AppStatusTone.info:
        return AppColors.advanceVioletLight;
      case AppStatusTone.neutral:
        return AppColors.surface2;
    }
  }

  Color get _fg {
    switch (tone) {
      case AppStatusTone.success:
        return AppColors.success;
      case AppStatusTone.danger:
        return AppColors.danger;
      case AppStatusTone.warning:
        return AppColors.warning;
      case AppStatusTone.info:
        return AppColors.advanceViolet;
      case AppStatusTone.neutral:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(color: _fg, height: 1.2, fontWeight: FontWeight.w700),
      ),
    );
  }
}
