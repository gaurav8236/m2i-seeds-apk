import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:logrocket_flutter/logrocket_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'l10n/generated/app_localizations.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/auth_service.dart';
import 'services/locale_service.dart';
import 'supabase_config.dart';
import 'theme.dart';
import 'utils/analytics.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    publishableKey: SupabaseConfig.supabaseAnonKey,
  );

  // wrapAndInitialize captures the full session replay from app launch.
  await LogRocket.wrapAndInitialize(
    LogRocketWrapConfiguration(),
    LogRocketInitConfiguration(appID: Analytics.appId),
    () => runApp(const SmartDukanApp()),
  );
}

class SmartDukanApp extends StatefulWidget {
  const SmartDukanApp({super.key});

  /// Lets any descendant (the design system's `LanguageSwitcher`) change
  /// the app's language at runtime. The standard Flutter pattern for
  /// runtime locale switching without a state-management package —
  /// consistent with this codebase's plain StatefulWidget/setState
  /// convention (see `mobile-developer`'s agent notes).
  static void setLocale(BuildContext context, Locale locale) {
    context.findAncestorStateOfType<_SmartDukanAppState>()?._setLocale(locale);
  }

  @override
  State<SmartDukanApp> createState() => _SmartDukanAppState();
}

class _SmartDukanAppState extends State<SmartDukanApp> {
  // Defaults to Hindi, not the device locale — matches the app's existing
  // Hindi-first hardcoded UI until a shopkeeper explicitly picks English.
  Locale _locale = const Locale('hi');

  @override
  void initState() {
    super.initState();
    _restoreSavedLocale();
  }

  Future<void> _restoreSavedLocale() async {
    final saved = await LocaleService.loadSavedLocale();
    if (saved != null && mounted) setState(() => _locale = saved);
  }

  void _setLocale(Locale locale) {
    setState(() => _locale = locale);
    LocaleService.saveLocale(locale);
  }

  @override
  Widget build(BuildContext context) {
    return LogRocketWidget(
      child: MaterialApp(
        title: 'SmartDukan',
        debugShowCheckedModeBanner: false,
        theme: appTheme,
        locale: _locale,
        supportedLocales: LocaleService.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        navigatorObservers: [LogRocketNavigatorObserver('smartdukan')],
        home: const AuthGate(),
      ),
    );
  }
}

// Listens to auth state — routes to LoginScreen, Onboarding, or AppShell.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? _seenOnboarding;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final seen = await AuthService.hasSeenOnboarding();
    if (mounted) setState(() => _seenOnboarding = seen);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: AuthService.authStateChanges,
      builder: (context, snapshot) {
        final session = AuthService.currentSession;
        if (session == null) {
          // Pop any pushed routes (customer detail, stock detail, etc.) so the
          // back button on LoginScreen doesn't return to an auth-required screen
          // (#13). Done in a post-frame callback to avoid modifying the navigator
          // during build.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          });
          return const LoginScreen();
        }

        AuthService.ensureUserRow();

        // Identify the LogRocket session once the user is authenticated.
        final user = AuthService.currentUser;
        if (user != null) {
          Analytics.identifyUser(
            userId: user.id,
            name: user.userMetadata?['full_name']?.toString(),
            email: user.email,
          );
        }

        if (_seenOnboarding == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!_seenOnboarding!) {
          return OnboardingScreen(
            onDone: () => setState(() => _seenOnboarding = true),
          );
        }

        return const AppShell();
      },
    );
  }
}
