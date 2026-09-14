// Confirming widget test for BUG-5a (`.claude/qa/BUGS.md`,
// `.claude/records/2026-09-13-bug5-architecture-review.md`).
//
// The refined hypothesis (still unconfirmed at the time this test was
// written): `AppShell`'s `PopScope(canPop: false)` (`lib/app.dart`) and
// `VoiceBillingScreen`'s own `PopScope(canPop: false)`
// (`lib/screens/voice_billing_screen.dart`, inside `_buildInput()`) both
// register against the *same* enclosing route (`VoiceBillingScreen` is an
// `IndexedStack` tab, never a pushed route of its own) — so a single back
// action invokes BOTH `onPopInvokedWithResult` callbacks. `AppShell`'s is
// synchronous; `VoiceBillingScreen`'s is `async` and calls
// `await _autoSaveDraft()`, which has a real async gap
// (`DraftService.saveDraft` → `SharedPreferences.getInstance()`).
//
// Per the task's step 1: try to force the same element-lifecycle
// inconsistency by triggering a pop, and — before that async gap
// resolves — triggering another back-navigation attempt (since
// `VoiceBillingScreen`'s `PopScope` stays registered against the route
// even while its tab is offstage in the `IndexedStack`, a second back
// press anywhere re-invokes it while the first `_autoSaveDraft()` call may
// still be in flight — the closest in-process analogue to the
// architecture review's "predictive-back preview started, then cancelled,
// racing the async callback" mechanism that a pure-Dart `flutter_test` can
// exercise, since the actual OS-level predictive-back preview animation
// itself is outside what `flutter_test`'s synthetic pump loop can drive).
//
// Uses the new `AppShell.initialTabForTest` / `.initialBillItemsForTest`
// and `VoiceBillingScreen.initialBillItemsForTest` test-only seams (see
// their doc comments in `lib/app.dart` / `lib/screens/voice_billing_screen.dart`)
// to land directly on the voice-billing tab with a non-empty bill, so
// `_autoSaveDraft()` takes its real async path instead of early-returning.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartdukan/app.dart';
import 'package:smartdukan/models/models.dart';

BillItem _oneBillItem() => BillItem(
      itemName: 'चावल',
      quantity: 2,
      pricePerUnit: 50,
      itemTotal: 100,
      stockRemaining: 8,
      currentStock: 10,
      unit: 'किलो',
    );

Future<NavigatorState> _pumpAppShellOnVoiceBillingTab(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: AppShell(
      initialTabForTest: 1, // voice-billing tab
      initialBillItemsForTest: [_oneBillItem()],
    ),
  ));
  // One settle for the initial frame + every tab's own failed-fast
  // Supabase/network calls in this test environment (each screen catches
  // its own errors internally, same as the existing BUG-5b test).
  await tester.pumpAndSettle();
  return tester.state<NavigatorState>(find.byType(Navigator));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'BUG-5a: a second back-navigation attempt while the first '
    '_autoSaveDraft() is still in flight must not throw',
    (tester) async {
      final navigator = await _pumpAppShellOnVoiceBillingTab(tester);

      // First back attempt: both PopScopes' onPopInvokedWithResult fire.
      // AppShell's is synchronous (switches to the Home tab). VoiceBilling
      // Screen's is async and starts `_autoSaveDraft()`, which reaches a
      // real async gap (`SharedPreferences.getInstance()`) and has not
      // resolved by the time this call returns.
      navigator.maybePop();

      // Deliberately no `pump()`/`pumpAndSettle()` here — trigger the
      // second back-navigation attempt while the first's async work is
      // still in flight. VoiceBillingScreen's PopScope stays registered
      // against the route even though its tab is now offstage (IndexedStack
      // never unmounts tabs), so this re-invokes its onPopInvokedWithResult
      // a second time, starting an overlapping `_autoSaveDraft()` call —
      // the same "two overlapping async invocations of the same handler"
      // shape as BUG-5b's confirmed (at the call-sequencing level) race,
      // applied to this bug's actual trigger action instead.
      navigator.maybePop();

      // Now let everything (both _autoSaveDraft() calls, both setState()s,
      // any resulting rebuilds) actually settle.
      await tester.pumpAndSettle();

      // The real assertion: no uncaught exception anywhere in that
      // settle — neither the `_dependents.isEmpty` assertion this bug's
      // hypothesis describes, nor anything else.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'BUG-5a: pumping a frame between two overlapping back-navigation '
    'attempts must not throw',
    (tester) async {
      final navigator = await _pumpAppShellOnVoiceBillingTab(tester);

      navigator.maybePop();
      // Pump a frame (rather than nothing) between the two attempts — the
      // task's alternate phrasing of the same race ("pump a frame ... to
      // see if you can force the same element-lifecycle inconsistency").
      await tester.pump();
      navigator.maybePop();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
}
