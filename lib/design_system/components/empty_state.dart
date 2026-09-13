import 'package:flutter/material.dart';
import '../../theme.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'app_button.dart';

/// Icon + short message + optional single action — replaces the
/// hand-rolled "no bills yet" style block duplicated per-screen (e.g.
/// `HomeScreen._recentBillsList`'s empty branch) with one reusable widget
/// in the same visual language.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: AppColors.borderStrong),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            style: AppTypography.body.copyWith(color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: actionLabel!,
              icon: actionIcon ?? Icons.refresh,
              onPressed: onAction,
              variant: AppButtonVariant.secondary,
              fullWidth: false,
            ),
          ],
        ],
      ),
    );
  }
}
