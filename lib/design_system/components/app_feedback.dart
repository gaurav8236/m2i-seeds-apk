import 'package:flutter/material.dart';
import '../../theme.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

enum _FeedbackKind { success, error, info }

/// Icon-forward `SnackBar` wrapper — every feedback message pairs a color
/// and icon with the text rather than relying on text alone, and stays on
/// screen longer than Flutter's default (a low-literacy reader needs more
/// time to read even a short sentence than a native reader does).
///
/// A static helper, not a widget — matches `AppDialogs.confirm`.
class AppFeedback {
  AppFeedback._();

  static void success(BuildContext context, String message) =>
      _show(context, message, _FeedbackKind.success);

  static void error(BuildContext context, String message) =>
      _show(context, message, _FeedbackKind.error);

  static void info(BuildContext context, String message) =>
      _show(context, message, _FeedbackKind.info);

  static void _show(BuildContext context, String message, _FeedbackKind kind) {
    final Color bg;
    final IconData icon;
    switch (kind) {
      case _FeedbackKind.success:
        bg = AppColors.success;
        icon = Icons.check_circle;
        break;
      case _FeedbackKind.error:
        bg = AppColors.danger;
        icon = Icons.error;
        break;
      case _FeedbackKind.info:
        bg = AppColors.primary;
        icon = Icons.info;
        break;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: bg,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(message, style: AppTypography.bodyStrong.copyWith(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
  }
}
