import 'package:flutter/material.dart';
import '../../theme.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

enum AppButtonVariant { primary, secondary, danger, ghost }

/// Primary tappable action across the design system.
///
/// Deliberately always icon + label, never icon-only — a bare icon asks a
/// low-literacy or first-time user to already know what it means. Height
/// is fixed comfortably above [AppSpacing.minTouchTarget] regardless of
/// variant. Stateless: variant/loading are fully prop-driven, and
/// `InkWell` already supplies visible tap feedback.
class AppButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool loading;
  final bool fullWidth;

  const AppButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.loading = false,
    this.fullWidth = true,
  });

  static const _bg = {
    AppButtonVariant.primary: AppColors.primary,
    AppButtonVariant.secondary: AppColors.surface,
    AppButtonVariant.danger: AppColors.danger,
    AppButtonVariant.ghost: Colors.transparent,
  };
  static const _fg = {
    AppButtonVariant.primary: Colors.white,
    AppButtonVariant.secondary: AppColors.textPrimary,
    AppButtonVariant.danger: Colors.white,
    AppButtonVariant.ghost: AppColors.primary,
  };

  @override
  Widget build(BuildContext context) {
    final bg = _bg[variant]!;
    final fg = _fg[variant]!;
    final disabled = onPressed == null || loading;

    final child = loading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
          )
        : Row(
            mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  style: AppTypography.bodyStrong.copyWith(color: fg),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      // 56 — comfortably above the 48dp minimum tap target.
      height: AppSpacing.minTouchTarget + 8,
      child: Material(
        color: disabled ? bg.withValues(alpha: 0.5) : bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: disabled ? null : onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            decoration: variant == AppButtonVariant.secondary
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.borderStrong),
                  )
                : null,
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}
