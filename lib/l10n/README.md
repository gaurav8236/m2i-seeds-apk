# Localization

Real `flutter_localizations`/`.arb` setup (see `l10n.yaml` at the repo
root). `app_en.arb` is the **template** — it is the source of truth for
which keys exist; every other `app_<code>.arb` must carry exactly the same
keys.

Currently seeded: `app_en.arb` (English), `app_hi.arb` (Hindi). These only
cover strings owned by `lib/design_system/` components (button/dialog
defaults, voice-input states, etc.) — the 11 existing screens under
`lib/screens/` still hardcode Hindi text directly and are **not** wired to
this system yet (see `docs/features/design-system.md`, Out of Scope).

## Adding a new key
1. Add it to `app_en.arb` with a `@key` description block.
2. Add the same key, translated, to `app_hi.arb`.
3. Run `flutter gen-l10n` (or just `flutter run`/`flutter build`, which
   regenerates automatically because `pubspec.yaml` has `generate: true`).
4. Use it via `AppLocalizations.of(context)!.yourKey`.

## Adding a new language later (e.g. Marathi, Gujarati)
1. Copy `app_en.arb` to `app_<code>.arb` (e.g. `app_mr.arb`), translate
   every value, keep every key identical.
2. Add `Locale('<code>')` to `LocaleService.supportedLocales`
   (`lib/services/locale_service.dart`).
3. Add the new option to `LanguageSwitcher`
   (`lib/design_system/components/language_switcher.dart`).

No other code changes needed — `AppLocalizations` regenerates its
delegate to include the new locale automatically.
