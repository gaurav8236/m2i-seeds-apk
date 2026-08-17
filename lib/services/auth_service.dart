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

  // In-memory cache so bill reprints don't need an extra network call.
  static String? _cachedShopName;

  /// Shop name cached from the last fetchProfile() call.
  /// Empty string if the user hasn't set one yet.
  static String get shopName => _cachedShopName ?? '';

  static bool _userRowEnsured = false;

  // Mirrors web's resolveUserId — guarantees a row exists in public.users
  static Future<void> ensureUserRow() async {
    if (_userRowEnsured) return;
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _supabase.from('users').upsert(
        {'id': user.id, 'created_at': now, 'updated_at': now},
        onConflict: 'id',
      );
      _userRowEnsured = true;
    } catch (_) {}
  }

  static Future<bool> hasSeenOnboarding() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return true;
    try {
      final res = await _supabase
          .from('users')
          .select('has_seen_onboarding')
          .eq('id', user.id)
          .single();
      return res['has_seen_onboarding'] == true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> markOnboardingComplete() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    await _supabase
        .from('users')
        .update({'has_seen_onboarding': true})
        .eq('id', user.id);
  }

  static Future<Map<String, String?>> fetchProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return {};
    try {
      final res = await _supabase
          .from('users')
          .select('display_name, shop_name')
          .eq('id', user.id)
          .single();
      _cachedShopName = res['shop_name']?.toString();
      return {
        'display_name': res['display_name']?.toString(),
        'shop_name': res['shop_name']?.toString(),
        'email': user.email,
        'photo_url': user.userMetadata?['avatar_url']?.toString(),
        'google_name': user.userMetadata?['full_name']?.toString(),
      };
    } catch (_) {
      return {
        'email': user.email,
        'google_name': user.userMetadata?['full_name']?.toString(),
        'photo_url': user.userMetadata?['avatar_url']?.toString(),
      };
    }
  }

  static Future<void> updateProfile({String? displayName, String? shopName}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final updates = <String, dynamic>{};
    if (displayName != null) updates['display_name'] = displayName;
    if (shopName != null) updates['shop_name'] = shopName;
    if (updates.isEmpty) return;
    await _supabase.from('users').update(updates).eq('id', user.id);
  }
}
