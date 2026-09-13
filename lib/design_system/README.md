# Design System

Foundation for Smart Dukan's mobile UI: shared tokens + a first set of
stateful components, built for a bilingual (Hindi/English, more Indian
languages later), low-tech-savvy shopkeeper audience. See
`docs/features/design-system.md` for the full design doc (problem
statement, approaches considered, decisions).

**Status: foundation only.** None of the 11 existing screens under
`lib/screens/` use this yet — that migration is a deliberately separate,
future task (see Out of Scope in the design doc). Use this for any *new*
screen or *changed* screen going forward.

## Principles
1. Icon + label on every action — never icon-only.
2. Every tappable element is ≥48dp (`AppSpacing.minTouchTarget`).
3. Text is large (16sp body, not 14) and generously line-spaced (≥1.4) —
   Devanagari needs more vertical room than Latin.
4. Labels stay visible above inputs — never hint-only.
5. State is shown, not just told (see `VoiceInputButton`'s pulse).
6. Feedback lingers — 4s snackbars, not the Flutter default.
7. Color always means the same thing — reuses `theme.dart`'s existing
   semantic `AppColors`, no new ad hoc colors introduced here.

## Tokens
- `tokens/spacing.dart` — `AppSpacing` (4/8/12/16/20/28 + the 48dp tap
  minimum), `AppRadius` (8/12/16/pill).
- `tokens/typography.dart` — `AppTypography` (display/heading/subheading/
  body/bodyStrong/label/caption).
- Colors: still `../theme.dart`'s `AppColors` — not duplicated here.

## Components

| Component | Use it for |
|---|---|
| `AppButton(label, icon, onPressed, variant, loading, fullWidth)` | Any primary/secondary/danger/ghost action. |
| `AppTextField(label, controller, errorText, obscureText, ...)` | Any form input; set `obscureText: true` for passwords (adds a reveal toggle). |
| `QuantityStepper(value, onChanged, min, max, step, unit)` | Adjusting a count (stock qty, bill line-item qty). |
| `VoiceInputButton(state, onTap)` | The mic affordance — `state` is `idle`/`listening`/`processing`. |
| `LanguageSwitcher()` | Drop in anywhere (e.g. Profile screen) to let the shopkeeper change language at runtime. |
| `AppFeedback.success/error/info(context, message)` | Any toast-style confirmation. |
| `EmptyState(icon, message, actionLabel?, onAction?)` | "Nothing here yet" states. |
| `AppDialogs.confirm(context, title:, message:, isDangerous:)` → `Future<bool>` | Any destructive/consequential confirmation. |
| `StatusBadge(label, tone)` | A single status word (paid/due/low-stock/advance). |

Import everything via the barrel file:
```dart
import 'package:smartdukan/design_system/design_system.dart';
```

## Localization
Component-internal strings (button/dialog defaults, voice-input states,
language names) go through the app's real `flutter_localizations` setup —
see `lib/l10n/README.md`. Get them via
`AppLocalizations.of(context)!.someKey`. This is genuinely wired
end-to-end (English + Hindi seeded); it does **not** cover the 11 existing
screens' hardcoded strings, which are untouched by this task.

## Previewing on a device/emulator
`lib/main_design_preview.dart` is a standalone entrypoint that renders
every component in this system without needing Supabase/LogRocket/auth —
useful for visually checking a change before wiring it into a real
screen:
```
flutter run -t lib/main_design_preview.dart
# or force a starting language for a screenshot/check:
flutter run -t lib/main_design_preview.dart --dart-define=PREVIEW_LOCALE=en
```
Its `LanguageSwitcher` is a no-op in this harness by design — that
component targets `SmartDukanApp`'s real state (`lib/main.dart`) via
`context.findAncestorStateOfType`, which doesn't exist in this standalone
tree. Verified working (English/Hindi both render correctly on-device,
`AppDialogs.confirm`, the voice button's state/animation, and the
feedback snackbar all confirmed live on a Pixel 8 emulator, API 30) —
only the tap-driven `SmartDukanApp.setLocale` path itself relies on
Flutter's standard runtime-locale-switch pattern and hasn't been
independently exercised end-to-end (would require a real screen using
`LanguageSwitcher`, which doesn't exist yet per this task's foundation-only
scope).

## Why some components are stateless
`AppButton`, `QuantityStepper`, `LanguageSwitcher`, `EmptyState`,
`StatusBadge` are all prop-driven/controlled (value or state owned by the
caller) rather than `StatefulWidget` — that's the more correct Flutter
pattern for props-in/event-out components (same pattern as `Slider` or
`Checkbox`) and avoids a second source of truth for state the caller
already owns. Real internal state lives in exactly three places:
`SmartDukanApp` (the active locale, in `lib/main.dart`), `AppTextField`
(the password-reveal toggle), and `VoiceInputButton` (the pulse
`AnimationController`).
