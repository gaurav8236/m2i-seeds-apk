import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logrocket_flutter/logrocket_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/auth_service.dart';
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

class SmartDukanApp extends StatelessWidget {
  const SmartDukanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return LogRocketWidget(
      child: MaterialApp(
        title: 'SmartDukan',
        debugShowCheckedModeBanner: false,
        theme: appTheme,
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
        if (session == null) return const LoginScreen();

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
