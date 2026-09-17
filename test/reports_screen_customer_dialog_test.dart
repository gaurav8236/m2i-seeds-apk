// Confirming widget test for BUG-11 (`.claude/qa/BUGS.md`).
//
// BUG-11's own entry explains why no confirming test existed yet: both
// `_showAddEntryDialog()` and `_showEditDialog()` (`_CustomerDetailScreenState`,
// `reports_screen.dart`) only reach their Navigator.pop + post-pop reload +
// controller-dispose sequence — the code adjacent to the crash — via a live
// Supabase/network call (`SupabaseService.recordPayment`/`recordDeposit`/
// `updateCustomer`), which isn't mocked anywhere in this suite and fails
// fast in the test environment (Supabase.initialize() is never called here).
// Without a seam, tapping "दर्ज करें"/"सहेजें" in a test would only ever hit
// the dialogs' `catch (e)` branch, never the success path this bug is about.
//
// This test uses the new `customerDetailScreenForTest()` factory + the
// `_CustomerDetailScreen.recordPaymentForTest`/`recordDepositForTest`/
// `updateCustomerForTest` injection points (added for this confirmation,
// mirroring `VoiceBillingScreen.initialStockForTest`'s seam from BUG-5b) to
// drive both dialogs through a real (mocked) success + close sequence,
// deterministically, without a real network call succeeding or failing
// unpredictably.
//
// Run against the current code, which already has hypothesis #2 (unfocus
// before pop) plus hypothesis #1's frame-deferral in place for both dialogs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartdukan/models/models.dart';
import 'package:smartdukan/screens/reports_screen.dart';

Customer _testCustomer({double openingBalance = 500}) {
  return Customer(
    id: 'test-customer-1',
    name: 'BUG-11 Test Customer',
    phone: '9876543210',
    openingBalance: openingBalance,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  testWidgets(
    'BUG-11: recording a payment via "दर्ज करें" must not throw',
    (tester) async {
      final customer = _testCustomer();

      await tester.pumpWidget(MaterialApp(
        home: customerDetailScreenForTest(
          customer: customer,
          // Mocked success — no real network/Supabase call. Small delay
          // mirrors the real awaited HTTP round-trip so the dialog's
          // 'submitting' spinner state and pop timing are exercised too.
          recordPayment: ({required customerName, required amount}) =>
              Future<void>.delayed(const Duration(milliseconds: 20)),
        ),
      ));
      await tester.pumpAndSettle();

      // Open the "record entry" dialog.
      await tester.tap(find.text('लेन-देन दर्ज करें'));
      await tester.pumpAndSettle();

      // Fill in a valid amount (payment is selected by default).
      await tester.enterText(find.byType(TextFormField).first, '250');
      await tester.pumpAndSettle();

      // Confirm.
      await tester.tap(find.text('दर्ज करें'));
      // Let the (mocked, delayed) submit resolve, the dialog's unfocus +
      // pop + closing transition play out, and the deferred post-pop
      // reload/snackbar + controller dispose all run to completion.
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'BUG-11: recording a deposit via "दर्ज करें" must not throw',
    (tester) async {
      final customer = _testCustomer();

      await tester.pumpWidget(MaterialApp(
        home: customerDetailScreenForTest(
          customer: customer,
          recordDeposit: ({required customerName, required amount}) =>
              Future<void>.delayed(const Duration(milliseconds: 20)),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('लेन-देन दर्ज करें'));
      await tester.pumpAndSettle();

      // Switch to "अग्रिम जमा" (deposit).
      await tester.tap(find.text('अग्रिम जमा'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '300');
      await tester.pumpAndSettle();

      await tester.tap(find.text('दर्ज करें'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'BUG-11: editing customer phone/balance via "सहेजें" must not throw',
    (tester) async {
      final customer = _testCustomer();

      await tester.pumpWidget(MaterialApp(
        home: customerDetailScreenForTest(
          customer: customer,
          updateCustomer: ({required id, phone, openingBalance}) =>
              Future<void>.delayed(const Duration(milliseconds: 20)),
        ),
      ));
      await tester.pumpAndSettle();

      // Open the overflow menu and tap "edit".
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('संपादित करें'));
      await tester.pumpAndSettle();

      // Change the balance (2nd TextFormField in the edit dialog: phone,
      // then opening balance).
      final balanceField = find.byType(TextFormField).at(1);
      await tester.enterText(balanceField, '750');
      await tester.pumpAndSettle();

      await tester.tap(find.text('सहेजें'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
}
