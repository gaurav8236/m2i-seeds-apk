import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final _supabase = Supabase.instance.client;

  static final _googleSignIn = GoogleSignIn(
    serverClientId: '814423599719-fkbbdvd4k0p2c397lnthe0h2v8ob4c7f.apps.googleusercontent.com',
  );

  static Future<void> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) throw Exception('Sign in cancelled');

    final googleAuth = await googleUser.authentication;
    if (googleAuth.idToken == null) throw Exception('No ID token received');

    await _supabase.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: googleAuth.idToken!,
      accessToken: googleAuth.accessToken,
    );
  }

  static Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _supabase.auth.signOut();
  }

  static Session? get currentSession => _supabase.auth.currentSession;
  static User? get currentUser => _supabase.auth.currentUser;
  static String? get userId => _supabase.auth.currentUser?.id;
  static bool get isLoggedIn => _supabase.auth.currentSession != null;
  static Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  static bool _userRowEnsured = false;

  // Mirrors web's resolveUserId — guarantees a row exists in public.users
  static Future<void> ensureUserRow() async {
    if (_userRowEnsured) return;
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final now = DateTime.now().toIso8601String();
      await _supabase.from('users').upsert(
        {'id': user.id, 'created_at': now, 'updated_at': now},
        onConflict: 'id',
      );
      _userRowEnsured = true;
    } catch (_) {}
  }
}
