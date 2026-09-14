// Confirming widget test for BUG-5b (`.claude/qa/BUGS.md`,
// `.claude/records/2026-09-13-bug5-architecture-review.md`).
//
// Per the Architect's step 1: reproduce the exact race a real impatient
// double-tap on "हाथ से बनाएं" would cause — two taps landing within the
// same pending-frame window, something scripted `adb shell input tap`
// passes could not reliably force (each `adb` invocation's process-spawn
// overhead is very likely >1 frame even issued back-to-back). `flutter_test`
// gives deterministic control here: two `tester.tap()` calls with no
// `pump()` between them force both `_addManualItem()` invocations to run
// before either's pending rebuild/postFrameCallback has a chance to
// settle — the exact scenario the architecture review's primary hypothesis
// describes.
//
// This test is written FIRST, run against the code as it stood before any
// reentrancy guard was added (the already-applied single-invocation fix
// from earlier today — `addPostFrameCallback` deferring `_showItemPicker`,
// but with no guard against a *second*, overlapping `_addManualItem()`
// call) — per the Architect's explicit instruction not to implement
// Approach A speculatively before confirming it's needed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartdukan/screens/voice_billing_screen.dart';

Future<void> _pumpVoiceBillingScreen(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: VoiceBillingScreen(onRegisterReload: (_) {}),
  ));
  // One settle for the initial frame + _loadData()'s async Supabase calls
  // (which fail fast in this test environment — Supabase.initialize() is
  // never called — and are caught internally by _loadData()'s own
  // try/catch, surfacing only as a harmless snackbar, not an exception).
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'BUG-5b: double-tapping "हाथ से बनाएं" with no pump() between taps '
    'must not throw',
    (tester) async {
      await _pumpVoiceBillingScreen(tester);

      final manualAddFinder = find.text('हाथ से बनाएं');
      expect(manualAddFinder, findsOneWidget);

      // The exact race: two taps, zero pumps in between. Each tap's
      // GestureDetector.onTap fires _addManualItem() synchronously as part
      // of tester.tap()'s event dispatch, before any frame is pumped — so
      // both invocations run back-to-back against the same pre-rebuild
      // state, exactly as two physical taps landing inside one ~16ms frame
      // window would.
      await tester.tap(manualAddFinder);
      await tester.tap(manualAddFinder);

      // Now let everything (rebuilds, postFrameCallbacks, modal route
      // transitions) actually settle.
      await tester.pumpAndSettle();

      // The real assertion: no uncaught exception anywhere in that
      // settle — neither the `_dependents.isEmpty` assertion the
      // architecture review hypothesized, nor the `RangeError` from the
      // secondary (stale-index) hypothesis, nor anything else.
      expect(tester.takeException(), isNull);
    },
  );
}
