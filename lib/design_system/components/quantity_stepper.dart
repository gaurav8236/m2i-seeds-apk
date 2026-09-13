import 'package:flutter/material.dart';
import '../../theme.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// Big-target +/- quantity control, used anywhere a shopkeeper adjusts a
/// count (stock quantity, bill line-item quantity) instead of typing a
/// number — tapping a large, obvious +/- is faster and less error-prone
/// for this audience than typing and risking a stray digit.
///
/// A controlled component (value owned by the caller, same pattern as
/// Flutter's own `Slider`/`Checkbox`) rather than internal state — avoids
/// a second source of truth for the same number.
///
/// Note: no press-and-hold auto-repeat yet (deferred — see
/// `.claude/TODOS.md` — typical adjustments here are small, single-digit
/// counts where repeated taps are fine).
class QuantityStepper extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;

  /// Optional unit label shown under the value, e.g. "किलो" / "KG".
  final String? unit;

  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 9999,
    this.step = 1,
    this.unit,
  });

  void _change(double delta) {
    final next = (value + delta).clamp(min, max);
    if (next != value) onChanged(next);
  }

  Widget _circleButton({required IconData icon, required VoidCallback? onTap}) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? AppColors.primaryLight : AppColors.surface2,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: AppSpacing.minTouchTarget,
          height: AppSpacing.minTouchTarget,
          child: Icon(icon, size: 22, color: enabled ? AppColors.primary : AppColors.textMuted),
        ),
      ),
    );
  }

  String get _display {
    final isWhole = value == value.roundToDouble();
    return isWhole ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _circleButton(icon: Icons.remove, onTap: value > min ? () => _change(-step) : null),
        Container(
          constraints: const BoxConstraints(minWidth: 56),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_display, style: AppTypography.heading),
              if (unit != null) Text(unit!, style: AppTypography.caption),
            ],
          ),
        ),
        _circleButton(icon: Icons.add, onTap: value < max ? () => _change(step) : null),
      ],
    );
  }
}
