import 'package:flutter/material.dart';
import '../../theme.dart';

/// Design-system type scale.
///
/// Sizes run larger than a typical consumer app's, and line-heights run
/// generous (>=1.4) rather than the usual ~1.2 — both deliberate for this
/// audience: shopkeepers who may be older, reading in low light behind a
/// counter, and switching between Latin and Devanagari script, whose
/// conjunct/matra glyphs need more vertical room than Latin to stay
/// legible at speed. Don't tighten these to match a generic style guide.
class AppTypography {
  AppTypography._();

  static const _base = TextStyle(color: AppColors.textPrimary, height: 1.5);

  static final display = _base.copyWith(
      fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.3);
  static final heading = _base.copyWith(fontSize: 20, fontWeight: FontWeight.w700);
  static final subheading = _base.copyWith(fontSize: 17, fontWeight: FontWeight.w600);
  static final body = _base.copyWith(fontSize: 16);
  static final bodyStrong = _base.copyWith(fontSize: 16, fontWeight: FontWeight.w700);
  static final label = _base.copyWith(fontSize: 15, fontWeight: FontWeight.w600);
  static final caption = _base.copyWith(
      fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary, height: 1.4);

  /// Floor for anything the shopkeeper must read to act (amounts, item
  /// names, confirmations). [caption] is the smallest allowed size and is
  /// reserved for secondary/decorative context only — don't go below it
  /// for anything load-bearing.
  static const double minReadableSize = 13;
}
