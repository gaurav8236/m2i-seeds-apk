import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';
import 'app_button.dart';

/// Icon-forward confirm/cancel dialog. Every destructive or consequential
/// action (delete customer, void a bill, etc.) should route through this
/// instead of a bare `AlertDialog`, so confirmations look and behave the
/// same everywhere. A static helper, not a widget — matches `AppFeedback`.
class AppDialogs {
  AppDialogs._();

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String? confirmLabel,
    String? cancelLabel,
    bool isDangerous = false,
  }) async {
    final t = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        icon: Icon(
          isDangerous ? Icons.warning_amber_rounded : Icons.help_outline,
          color: isDangerous ? AppColors.danger : AppColors.primary,
          size: 32,
        ),
        title: Text(title, style: AppTypography.heading, textAlign: TextAlign.center),
        content: Text(message, style: AppTypography.body, textAlign: TextAlign.center),
        actionsPadding:
            const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        // AlertDialog lays `actions` out via an internal OverflowBar, not a
        // Flex — Expanded can't go directly in that list (crashes with
        // "Incorrect use of ParentDataWidget", caught by
        // test/design_system_test.dart). Wrapping both buttons in one Row
        // and passing that single Row as the action gives Expanded a real
        // Flex ancestor.
        actions: [
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: cancelLabel ?? t.commonCancel,
                  icon: Icons.close,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => Navigator.of(ctx).pop(false),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  label: confirmLabel ?? t.commonConfirm,
                  icon: Icons.check,
                  variant: isDangerous ? AppButtonVariant.danger : AppButtonVariant.primary,
                  onPressed: () => Navigator.of(ctx).pop(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
