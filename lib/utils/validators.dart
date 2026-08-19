/// Shared input validators for SmartDukan Flutter app.
///
/// Each function returns null on success, or a Hindi error string on failure.
/// All validation rules match the DB invariants and admin validators (validators.ts).
class Validators {
  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Returns true if [v] has at most 1 decimal place (e.g. 39.5 ✓, 39.55 ✗).
  static bool isOneDecimal(double v) => (v * 10).roundToDouble() == v * 10;

  // ── Profile ───────────────────────────────────────────────────────────────

  /// Display name — required, 2–60 chars, no spaces-only (#10 #11).
  static String? displayName(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'नाम भरें';
    if (s.length < 2) return 'नाम कम से कम 2 अक्षर का होना चाहिए';
    if (s.length > 60) return 'नाम 60 अक्षर से अधिक नहीं हो सकता';
    return null;
  }

  /// Shop name — optional; if non-empty, 2–60 chars, no spaces-only (#14).
  static String? shopName(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return null; // optional
    if (s.length < 2) return 'दुकान का नाम कम से कम 2 अक्षर का होना चाहिए';
    if (s.length > 60) return 'दुकान का नाम 60 अक्षर से अधिक नहीं हो सकता';
    return null;
  }

  // ── Inventory ─────────────────────────────────────────────────────────────

  /// Item name — 2–50 chars; letters, digits, Hindi, spaces only (#21).
  static String? itemName(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'सामान का नाम भरें';
    if (s.length < 2) return 'नाम कम से कम 2 अक्षर का होना चाहिए';
    if (s.length > 50) return 'नाम 50 अक्षर से अधिक नहीं हो सकता';
    // Allow: letters (Latin + Devanagari), digits, spaces, hyphens, dots
    if (!RegExp(r"^[\wऀ-ॿ\s.\-]+$").hasMatch(s)) {
      return 'नाम में केवल अक्षर, अंक और स्पेस इस्तेमाल करें';
    }
    return null;
  }

  /// Alias (bolne ka naam) — 1–50 chars, non-empty (#24).
  static String? alias(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'बोलने का नाम भरें';
    if (s.length > 50) return 'नाम 50 अक्षर से अधिक नहीं हो सकता';
    return null;
  }

  /// Selling price — must be ≥ 0, < 50,000. DB enforces ≥ 0.
  static String? sellingPrice(String? v) {
    if (v == null || v.trim().isEmpty) return 'कीमत भरें';
    final n = double.tryParse(v.trim());
    if (n == null) return 'कीमत सही नहीं है';
    if (n < 0) return 'कीमत 0 से कम नहीं हो सकती';
    if (n >= 50000) return 'कीमत ₹49,999 से अधिक नहीं हो सकती';
    return null;
  }

  /// Current stock — must be ≥ 0, ≤ 1,00,000, at most 1 decimal place.
  /// DB enforces ≥ 0; decimal precision is input-level only.
  static String? currentStock(String? v) {
    if (v == null || v.trim().isEmpty) return 'स्टॉक भरें';
    final n = double.tryParse(v.trim());
    if (n == null) return 'स्टॉक सही नहीं है';
    if (n < 0) return 'स्टॉक 0 से कम नहीं हो सकता';
    if (n > 100000) return 'स्टॉक 1,00,000 से अधिक नहीं हो सकता';
    if (!isOneDecimal(n)) {
      return 'स्टॉक में एक दशमलव तक ही अनुमत है (जैसे: 39.5)';
    }
    return null;
  }

  // ── Customers ─────────────────────────────────────────────────────────────

  /// Customer name — required, max 80 chars, no special chars (#37).
  static String? customerName(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'नाम भरें';
    if (s.length > 80) return 'नाम 80 अक्षर से अधिक नहीं हो सकता';
    // Disallow special chars that cause ledger-key collisions
    if (RegExp(r'[<>"\{\}\[\]\\|]').hasMatch(s)) {
      return 'नाम में विशेष चिह्न न डालें';
    }
    return null;
  }

  /// Phone — optional field. If provided, must be exactly 10 digits.
  static String? phone(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return null; // optional
    if (!RegExp(r'^\d{10}$').hasMatch(s)) {
      return 'फ़ोन नंबर 10 अंकों का होना चाहिए';
    }
    return null;
  }

  // ── Payments ──────────────────────────────────────────────────────────────

  /// Payment amount — must be > 0.
  static String? paymentAmount(String? v) {
    if (v == null || v.trim().isEmpty) return 'राशि भरें';
    final n = double.tryParse(v.trim());
    if (n == null) return 'राशि सही नहीं है';
    if (n <= 0) return 'राशि 0 से अधिक होनी चाहिए';
    return null;
  }

  /// Opening balance — optional, must be ≥ 0 if provided.
  static String? openingBalance(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return null; // defaults to 0
    final n = double.tryParse(s);
    if (n == null) return 'राशि सही नहीं है';
    if (n < 0) return 'शुरुआती बकाया 0 से कम नहीं हो सकता';
    return null;
  }

  /// Discount amount — must be ≥ 0.
  static String? discount(String? v) {
    if (v == null || v.trim().isEmpty) return null; // 0 if blank
    final n = double.tryParse(v.trim());
    if (n == null) return 'छूट सही नहीं है — केवल संख्या डालें';
    if (n < 0) return 'छूट 0 से कम नहीं हो सकती';
    return null;
  }
}
