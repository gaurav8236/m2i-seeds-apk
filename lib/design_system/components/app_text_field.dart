import 'package:flutter/material.dart';
import '../../theme.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// Text input with an always-visible label (never hint-only — a hint that
/// vanishes on focus is easy to lose track of for someone unfamiliar with
/// form conventions), a generously sized type area, and an inline error
/// row with an icon rather than just red text.
///
/// Stateful: owns a real internal toggle (`_obscured`) for password-style
/// fields, so the shopkeeper can reveal what they typed via an eye icon —
/// genuine internal state, not just controller passthrough.
class AppTextField extends StatefulWidget {
  final String label;
  final TextEditingController? controller;
  final String? errorText;
  final String? hint;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final Widget? trailing;
  final bool obscureText;

  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.errorText,
    this.hint,
    this.keyboardType,
    this.onChanged,
    this.trailing,
    this.obscureText = false,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscured = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: widget.controller,
          keyboardType: widget.keyboardType,
          obscureText: _obscured,
          onChanged: widget.onChanged,
          style: AppTypography.body,
          decoration: InputDecoration(
            hintText: widget.hint,
            suffixIcon: widget.obscureText
                ? IconButton(
                    icon: Icon(_obscured
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    color: AppColors.textMuted,
                    onPressed: () => setState(() => _obscured = !_obscured),
                  )
                : widget.trailing,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: BorderSide(
                  color: hasError ? AppColors.danger : AppColors.border,
                  width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: BorderSide(
                  color: hasError ? AppColors.danger : AppColors.primary,
                  width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.errorText!,
                  style: AppTypography.caption.copyWith(color: AppColors.danger),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
