import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps exceptions to Hindi messages a shopkeeper can actually act on.
///
/// Use this instead of interpolating the raw exception (`'त्रुटि: $e'`)
/// into UI text — Dart/platform exception strings (e.g. `SocketException`,
/// `ClientException`) are English, technical, and meaningless to the user.
class Errors {
  /// Returns a Hindi message for [e]. Callers that already have a more
  /// specific mapping (e.g. a known Postgres error code) should check that
  /// first and fall back to this only for the unrecognized case.
  static String friendlyMessage(Object e) {
    if (_isNetworkError(e)) {
      return 'इंटरनेट कनेक्शन नहीं है। कृपया नेटवर्क जांचें और दोबारा कोशिश करें।';
    }
    if (e is TimeoutException) {
      return 'सर्वर से जवाब मिलने में देर हो रही है। कृपया दोबारा कोशिश करें।';
    }
    if (e is AuthException) {
      return 'लॉगिन की समस्या — कृपया दोबारा लॉगिन करें।';
    }
    return 'कुछ गड़बड़ हो गई। कृपया दोबारा कोशिश करें।';
  }

  static bool _isNetworkError(Object e) {
    if (e is SocketException || e is TimeoutException) return true;
    // supabase_flutter/http wrap SocketException inside ClientException;
    // its toString() is the only reliable signal without depending on
    // the http package's ClientException type directly here.
    final s = e.toString();
    return s.contains('SocketException') ||
        s.contains('ClientException') ||
        s.contains('Network is unreachable') ||
        s.contains('Connection failed') ||
        s.contains('Connection refused') ||
        s.contains('Connection timed out');
  }
}
