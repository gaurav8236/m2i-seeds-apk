import 'package:flutter/foundation.dart';
import 'package:logrocket_flutter/logrocket_flutter.dart';

/// Central analytics wrapper around LogRocket.
/// All product events flow through here — never call LogRocket directly.
///
/// App ID: wzlqix/seeds-01  (same project as web frontend)
///
/// EVENT CATALOGUE
/// ───────────────────────────────────────────────────────────────────
/// Auth
///   login_started          — user taps "Sign in with Google"
///   login_success          — Google sign-in completed
///   login_failed           — sign-in threw an error  [reason: String]
///   logout                 — user signed out from profile screen
///
/// Onboarding
///   onboarding_completed   — user tapped Done on onboarding screen
///
/// Voice Billing
///   voice_session_opened   — user opens the recording screen (mic button tapped)
///   mic_permission_denied  — mic permission not granted
///   recording_started      — recording actually began
///   recording_stopped      — user tapped stop (normal flow)
///   voice_api_success      — backend returned ≥1 matched items
///                            [items_found: Int, items_matched: Int]
///   voice_api_no_items     — backend returned 0 items  [reason: String]
///   voice_api_error        — backend call failed  [error: String]
///   bill_item_added_manual — user added an item by hand (not via voice)
///   bill_item_removed      — user removed a line item
///   bill_proceed_checkout  — user tapped "Proceed" to settlement screen
///                            [item_count: Int]
///   bill_confirmed         — bill finalized and saved to Supabase
///                            [total_amount: Double, is_credit: Bool, item_count: Int]
///   bill_pdf_downloaded    — user downloaded the PDF
///   bill_pdf_shared        — user shared PDF (WhatsApp / other)
///   bill_draft_saved       — draft auto-saved
///   bill_draft_resumed     — user resumed a saved draft
///
/// Inventory
///   low_stock_alert_shown  — low-stock banner visible on home  [count: Int]
///   stock_item_viewed      — user opened a stock item detail  [item_name: String]
///
/// Customers
///   customer_added         — new customer created
///
/// Profile
///   profile_updated        — shop name / display name saved
/// ───────────────────────────────────────────────────────────────────

class Analytics {
  Analytics._();

  static const String appId = 'wzlqix/seeds-01';

  /// Call once after the user successfully logs in.
  static void identifyUser({
    required String userId,
    String? name,
    String? email,
    String? shopName,
  }) {
    try {
      final info = <String, String>{
        'platform': 'flutter_android',
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (shopName != null) 'shopName': shopName,
      };
      LogRocket.identify(userId, info);
    } catch (e) {
      debugPrint('[Analytics] identify failed: $e');
    }
  }

  // ── Auth ──────────────────────────────────────────────────────────

  static void loginStarted() => _track('login_started');
  static void loginSuccess() => _track('login_success');
  static void loginFailed(String reason) =>
      _track('login_failed', (e) => e..putString('reason', reason));
  static void logout() => _track('logout');

  // ── Onboarding ───────────────────────────────────────────────────

  static void onboardingCompleted() => _track('onboarding_completed');

  // ── Voice Billing ─────────────────────────────────────────────────

  static void voiceSessionOpened() => _track('voice_session_opened');
  static void micPermissionDenied() => _track('mic_permission_denied');
  static void recordingStarted() => _track('recording_started');
  static void recordingStopped() => _track('recording_stopped');

  static void voiceApiSuccess({required int itemsFound, required int itemsMatched}) =>
      _track('voice_api_success', (e) => e
        ..putInt('items_found', itemsFound)
        ..putInt('items_matched', itemsMatched));

  static void voiceApiNoItems({String reason = ''}) =>
      _track('voice_api_no_items', (e) => e..putString('reason', reason));

  static void voiceApiError({required String error}) =>
      _track('voice_api_error', (e) => e..putString('error', error));

  static void billItemAddedManual() => _track('bill_item_added_manual');
  static void billItemRemoved() => _track('bill_item_removed');

  static void billProceedCheckout({required int itemCount}) =>
      _track('bill_proceed_checkout', (e) => e..putInt('item_count', itemCount));

  static void billConfirmed({
    required double totalAmount,
    required bool isCredit,
    required int itemCount,
  }) =>
      _track('bill_confirmed', (e) => e
        ..putDouble('total_amount', totalAmount)
        ..putBool('is_credit', isCredit)
        ..putInt('item_count', itemCount));

  static void billPdfDownloaded() => _track('bill_pdf_downloaded');
  static void billPdfShared() => _track('bill_pdf_shared');
  static void billDraftSaved() => _track('bill_draft_saved');
  static void billDraftResumed() => _track('bill_draft_resumed');
  static void billCancelled({required int itemCount}) =>
      _track('bill_cancelled', (e) => e..putInt('item_count', itemCount));

  // ── Inventory ─────────────────────────────────────────────────────

  static void lowStockAlertShown({required int count}) =>
      _track('low_stock_alert_shown', (e) => e..putInt('count', count));

  static void stockItemViewed({required String itemName}) =>
      _track('stock_item_viewed', (e) => e..putString('item_name', itemName));

  // ── Customers ─────────────────────────────────────────────────────

  static void customerAdded() => _track('customer_added');

  // ── Profile ───────────────────────────────────────────────────────

  static void profileUpdated() => _track('profile_updated');

  // ── Internal ──────────────────────────────────────────────────────

  static void _track(String eventName,
      [void Function(LogRocketCustomEventBuilder)? builder]) {
    try {
      final event = LogRocketCustomEventBuilder(eventName);
      builder?.call(event);
      LogRocket.track(event);
      debugPrint('[Analytics] $eventName');
    } catch (e) {
      debugPrint('[Analytics] track "$eventName" failed: $e');
    }
  }
}
