/// Spacing scale for the design system. Use these instead of ad hoc
/// numbers so rhythm stays consistent as new screens adopt the system.
class AppSpacing {
  AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;

  /// Minimum side length for any tappable element, per Android's own
  /// accessibility guidance (48dp). Every interactive design-system
  /// component enforces at least this — don't shrink a tap target below it
  /// to fit more on screen.
  static const minTouchTarget = 48.0;
}

/// Corner-radius scale, shared by every design-system component so
/// rounding reads as one visual language rather than per-widget choices.
class AppRadius {
  AppRadius._();

  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const pill = 999.0;
}
