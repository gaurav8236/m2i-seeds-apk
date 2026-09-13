import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the shopkeeper's chosen app language across launches.
///
/// A thin static-method service, matching every other service in this
/// codebase (see `AuthService`) — no state-management package involved.
class LocaleService {
  LocaleService._();

  static const _prefsKey = 'app_locale';

  /// Languages the app actually ships translations for. Add a new
  /// `Locale(...)` here (after adding the matching `app_<code>.arb` — see
  /// `lib/l10n/README.md`) to support another Indian language.
  static const supportedLocales = [Locale('hi'), Locale('en')];

  /// Returns the previously-saved locale, or null if the shopkeeper hasn't
  /// picked one explicitly yet (caller should fall back to the app default).
  static Future<Locale?> loadSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefsKey);
    if (code == null) return null;
    for (final locale in supportedLocales) {
      if (locale.languageCode == code) return locale;
    }
    return null;
  }

  static Future<void> saveLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, locale.languageCode);
  }
}
