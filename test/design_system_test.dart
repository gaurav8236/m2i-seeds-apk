// Smoke tests for the mobile design system + its l10n wiring
// (docs/features/design-system.md). No widget-test precedent existed in
// this repo before this file — added specifically to get real evidence
// (not just `flutter analyze`) that English/Hindi actually resolve
// correctly and every new component renders without throwing in both
// locales.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartdukan/design_system/design_system.dart';
import 'package:smartdukan/l10n/generated/app_localizations.dart';
import 'package:smartdukan/services/locale_service.dart';

Widget _wrap(Widget child, Locale locale) {
  return MaterialApp(
    locale: locale,
    supportedLocales: LocaleService.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );
}

void main() {
  group('AppLocalizations resolves the right strings per locale', () {
    testWidgets('English', (tester) async {
      late AppLocalizations t;
      await tester.pumpWidget(_wrap(
        Builder(builder: (context) {
          t = AppLocalizations.of(context);
          return const SizedBox();
        }),
        const Locale('en'),
      ));
      expect(t.commonCancel, 'Cancel');
      expect(t.commonConfirm, 'Confirm');
      expect(t.voiceInputTapToSpeak, 'Tap to speak');
      expect(t.voiceInputListening, 'Listening...');
      expect(t.languageHindi, 'Hindi');
      expect(t.languageEnglish, 'English');
    });

    testWidgets('Hindi', (tester) async {
      late AppLocalizations t;
      await tester.pumpWidget(_wrap(
        Builder(builder: (context) {
          t = AppLocalizations.of(context);
          return const SizedBox();
        }),
        const Locale('hi'),
      ));
      expect(t.commonCancel, 'रद्द करें');
      expect(t.commonConfirm, 'पुष्टि करें');
      expect(t.voiceInputTapToSpeak, 'बोलने के लिए दबाएं');
      expect(t.voiceInputListening, 'सुन रहा हूँ...');
      expect(t.languageHindi, 'हिंदी');
      expect(t.languageEnglish, 'अंग्रेज़ी');
    });
  });

  group('Every design-system component renders without error, in both locales', () {
    for (final locale in [const Locale('en'), const Locale('hi')]) {
      testWidgets('locale=${locale.languageCode}', (tester) async {
        await tester.pumpWidget(_wrap(
          SingleChildScrollView(
            child: Column(
              children: [
                AppButton(label: 'Save', icon: Icons.check, onPressed: () {}),
                AppButton(
                    label: 'Loading', icon: Icons.check, onPressed: () {}, loading: true),
                AppButton(
                    label: 'Disabled', icon: Icons.check, onPressed: null),
                const AppTextField(label: 'Name'),
                const AppTextField(label: 'Password', obscureText: true),
                QuantityStepper(value: 2, onChanged: (_) {}, unit: 'KG'),
                VoiceInputButton(state: VoiceInputState.idle, onTap: () {}),
                VoiceInputButton(state: VoiceInputState.listening, onTap: () {}),
                VoiceInputButton(state: VoiceInputState.processing, onTap: () {}),
                const LanguageSwitcher(),
                EmptyState(
                  icon: Icons.inbox,
                  message: 'Nothing here',
                  actionLabel: 'Retry',
                  onAction: () {},
                ),
                const StatusBadge(label: 'Paid', tone: AppStatusTone.success),
                const StatusBadge(label: 'Due', tone: AppStatusTone.danger),
              ],
            ),
          ),
          locale,
        ));
        // Let the VoiceInputButton's pulse AnimationController tick at
        // least once instead of leaving it mid-flight.
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('AppTextField password reveal toggle flips obscureText', (tester) async {
    await tester.pumpWidget(_wrap(
      const AppTextField(label: 'Password', obscureText: true),
      const Locale('en'),
    ));

    final fieldFinder = find.byType(TextField);
    expect((tester.widget(fieldFinder) as TextField).obscureText, isTrue);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();

    expect((tester.widget(fieldFinder) as TextField).obscureText, isFalse);
  });

  testWidgets('LanguageSwitcher shows the right two labels per locale', (tester) async {
    await tester.pumpWidget(_wrap(const LanguageSwitcher(), const Locale('hi')));
    expect(find.text('हिंदी'), findsOneWidget);
    expect(find.text('अंग्रेज़ी'), findsOneWidget);

    await tester.pumpWidget(_wrap(const LanguageSwitcher(), const Locale('en')));
    expect(find.text('Hindi'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
  });

  testWidgets('AppDialogs.confirm shows localized default labels and returns the right bool',
      (tester) async {
    bool? result;
    await tester.pumpWidget(_wrap(
      Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            result = await AppDialogs.confirm(context, title: 'Delete?', message: 'Sure?');
          },
          child: const Text('open'),
        );
      }),
      const Locale('hi'),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('रद्द करें'), findsOneWidget); // commonCancel
    expect(find.text('पुष्टि करें'), findsOneWidget); // commonConfirm

    await tester.tap(find.text('पुष्टि करें'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  group('LocaleService persists the chosen locale', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('nothing saved yet -> null', () async {
      expect(await LocaleService.loadSavedLocale(), isNull);
    });

    test('save then load round-trips', () async {
      await LocaleService.saveLocale(const Locale('en'));
      expect((await LocaleService.loadSavedLocale())?.languageCode, 'en');
    });

    test('supportedLocales covers Hindi and English', () {
      final codes = LocaleService.supportedLocales.map((l) => l.languageCode);
      expect(codes, containsAll(['hi', 'en']));
    });
  });
}
