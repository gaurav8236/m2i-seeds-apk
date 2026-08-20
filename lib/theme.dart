import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF1A56DB);
  static const primaryDark = Color(0xFF0D47A1);
  static const primaryLight = Color(0xFFE8F0FE);
  static const success = Color(0xFF16A34A);
  static const successLight = Color(0xFFF0FDF4);
  static const danger = Color(0xFFDC2626);
  static const dangerLight = Color(0xFFFEF2F2);
  static const warning = Color(0xFFD97706);
  static const warningLight = Color(0xFFFFFBEB);
  static const bg = Color(0xFFF1F5F9);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF8FAFC);
  static const border = Color(0xFFE2E8F0);
  static const borderStrong = Color(0xFFCBD5E1);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF475569);
  static const textMuted = Color(0xFF64748B);
  /// WhatsApp brand green — used only for share-via-WhatsApp actions.
  static const whatsappGreen = Color(0xFF25D366);
  /// Advance / deposit semantic colour (violet).
  /// Used wherever a customer has pre-paid or we owe them a credit balance.
  static const advanceViolet      = Color(0xFF7C3AED);
  static const advanceVioletLight = Color(0xFFEDE9FE);
  /// Bright green for text/icons rendered on dark gradient surfaces
  /// (e.g. success screen header stats, highlighted totals on blue headers).
  static const successOnDark = Color(0xFF4ADE80);
  /// Two-stop gradient used on the bill-finalised success screen header.
  static const successGradientDark = Color(0xFF064E3B);
  static const successGradientMid  = Color(0xFF059669);
  /// Second gradient stop for the recording-active (danger) mic button.
  static const dangerMid = Color(0xFFEF4444);
  /// Dark green for italic text rendered over successLight backgrounds.
  static const successDarkText = Color(0xFF14532D);
}

final LinearGradient primaryGradient = const LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF0D47A1), Color(0xFF1976D2)],
);

final ThemeData appTheme = ThemeData(
  useMaterial3: true,
  fontFamily: 'Roboto',
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    surface: AppColors.surface,
    surfaceContainerLowest: AppColors.bg,
  ),
  scaffoldBackgroundColor: AppColors.bg,
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    elevation: 0,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surface2,
    hintStyle: const TextStyle(
      color: Color(0xFFB0BAC8),
      fontSize: 13,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.italic,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.border, width: 1.5),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.border, width: 1.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  ),
  cardTheme: CardThemeData(
    color: AppColors.surface,
    elevation: 1,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: AppColors.border),
    ),
    margin: const EdgeInsets.only(bottom: 12),
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: Colors.white,
    selectedItemColor: AppColors.primary,
    unselectedItemColor: AppColors.textMuted,
    type: BottomNavigationBarType.fixed,
    elevation: 8,
  ),
);
