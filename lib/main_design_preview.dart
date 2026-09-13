// Standalone entrypoint to visually preview lib/design_system/ components
// on a device/emulator without needing Supabase/LogRocket/auth wired up.
//
// Run with: flutter run -t lib/main_design_preview.dart
// Force a starting locale (for screenshot/verification purposes) with:
//   flutter run -t lib/main_design_preview.dart --dart-define=PREVIEW_LOCALE=en
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'design_system/design_system.dart';
import 'l10n/generated/app_localizations.dart';
import 'theme.dart';

const _initialLocaleCode = String.fromEnvironment('PREVIEW_LOCALE', defaultValue: 'hi');

void main() => runApp(const _DesignSystemPreviewApp());

class _DesignSystemPreviewApp extends StatefulWidget {
  const _DesignSystemPreviewApp();

  @override
  State<_DesignSystemPreviewApp> createState() => _DesignSystemPreviewAppState();
}

class _DesignSystemPreviewAppState extends State<_DesignSystemPreviewApp> {
  Locale _locale = const Locale(_initialLocaleCode);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Design System Preview',
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      locale: _locale,
      supportedLocales: const [Locale('hi'), Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: _PreviewScreen(
        onToggleLocale: () => setState(() {
          _locale = _locale.languageCode == 'hi' ? const Locale('en') : const Locale('hi');
        }),
      ),
    );
  }
}

class _PreviewScreen extends StatefulWidget {
  final VoidCallback onToggleLocale;
  const _PreviewScreen({required this.onToggleLocale});

  @override
  State<_PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<_PreviewScreen> {
  VoiceInputState _voiceState = VoiceInputState.idle;
  double _qty = 2;
  String? _fieldError;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Design System Preview')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LanguageSwitcher(),
              const SizedBox(height: AppSpacing.xl),
              Text('Buttons', style: AppTypography.heading),
              const SizedBox(height: AppSpacing.sm),
              AppButton(label: 'Primary', icon: Icons.check, onPressed: () {}),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                  label: 'Secondary',
                  icon: Icons.edit,
                  variant: AppButtonVariant.secondary,
                  onPressed: () {}),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                  label: 'Danger',
                  icon: Icons.delete,
                  variant: AppButtonVariant.danger,
                  onPressed: () {}),
              const SizedBox(height: AppSpacing.sm),
              AppButton(label: 'Loading', icon: Icons.check, loading: true, onPressed: () {}),
              const SizedBox(height: AppSpacing.xl),
              Text('Text field', style: AppTypography.heading),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(label: 'Item name', hint: 'e.g. Maggi', errorText: _fieldError),
              const SizedBox(height: AppSpacing.sm),
              const AppTextField(label: 'Password', obscureText: true),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'Toggle error',
                icon: Icons.error_outline,
                variant: AppButtonVariant.ghost,
                fullWidth: false,
                onPressed: () =>
                    setState(() => _fieldError = _fieldError == null ? 'यह ज़रूरी है' : null),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Quantity stepper', style: AppTypography.heading),
              const SizedBox(height: AppSpacing.sm),
              QuantityStepper(
                  value: _qty, unit: 'किलो', onChanged: (v) => setState(() => _qty = v)),
              const SizedBox(height: AppSpacing.xl),
              Text('Voice input', style: AppTypography.heading),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: VoiceInputButton(
                  state: _voiceState,
                  onTap: () => setState(() {
                    switch (_voiceState) {
                      case VoiceInputState.idle:
                        _voiceState = VoiceInputState.listening;
                        break;
                      case VoiceInputState.listening:
                        _voiceState = VoiceInputState.processing;
                        break;
                      case VoiceInputState.processing:
                        _voiceState = VoiceInputState.idle;
                        break;
                    }
                  }),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Status badges', style: AppTypography.heading),
              const SizedBox(height: AppSpacing.sm),
              const Wrap(spacing: AppSpacing.sm, children: [
                StatusBadge(label: 'Paid', tone: AppStatusTone.success),
                StatusBadge(label: 'Due', tone: AppStatusTone.danger),
                StatusBadge(label: 'Low stock', tone: AppStatusTone.warning),
                StatusBadge(label: 'Advance', tone: AppStatusTone.info),
              ]),
              const SizedBox(height: AppSpacing.xl),
              Text('Empty state', style: AppTypography.heading),
              const SizedBox(height: AppSpacing.sm),
              EmptyState(
                  icon: Icons.inbox,
                  message: 'कोई बिल नहीं',
                  actionLabel: 'फिर कोशिश करें',
                  onAction: () {}),
              const SizedBox(height: AppSpacing.xl),
              Row(children: [
                Expanded(
                  child: AppButton(
                    label: 'Feedback',
                    icon: Icons.notifications,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => AppFeedback.success(context, 'Saved!'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppButton(
                    label: 'Dialog',
                    icon: Icons.warning,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => AppDialogs.confirm(
                        context,
                        title: 'Delete?',
                        message: 'Are you sure?',
                        isDangerous: true),
                  ),
                ),
              ]),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
