// Regression test for BUG-13 (`.claude/qa/BUGS.md`) — `_reportsTab()`
// partitioned `_filteredBills` purely by the raw `Bill.isCredit` boolean,
// with no `transaction_type` exclusion, so `payment`/`deposit` rows (which
// have `is_credit=false`) were counted fully as cash-sales revenue in the
// "नकद बिक्री" / "उधार बिक्री" / "कुल बिक्री" summary cards.
//
// `_reportsTab()` itself lives on a private State and needs a live Supabase
// call (via `_load()`) to populate `_allBills` — not mocked anywhere in this
// suite (same constraint noted for BUG-11 in `.claude/qa/BUGS.md`). So this
// tests the pure summary computation extracted out for that reason,
// `computeReportsSalesSummary()` (@visibleForTesting), directly against
// `Bill` objects — same seam pattern as `bucketFilteredStats()` for BUG-12.
import 'package:flutter_test/flutter_test.dart';
import 'package:smartdukan/models/models.dart';
import 'package:smartdukan/screens/reports_screen.dart';

Bill _bill({
  required double totalAmount,
  required bool isCredit,
  required String transactionType,
  double nagadAmount = 0,
}) {
  return Bill(
    id: 'test-${DateTime.now().microsecondsSinceEpoch}-$transactionType-$totalAmount',
    createdAt: DateTime(2026, 9, 13),
    customerName: 'Test Customer',
    totalAmount: totalAmount,
    isCredit: isCredit,
    transactionType: transactionType,
    nagadAmount: nagadAmount,
    billDetails: const [],
  );
}

void main() {
  group('computeReportsSalesSummary (BUG-13)', () {
    test('a payment (debt repayment) is excluded from all three cards', () {
      final bills = [
        _bill(totalAmount: 400, isCredit: false, transactionType: 'payment'),
      ];

      final summary = computeReportsSalesSummary(bills);

      expect(summary.cashTotal, 0);
      expect(summary.creditTotal, 0);
      expect(summary.cashCount, 0);
      expect(summary.creditCount, 0);
      expect(summary.salesCount, 0);
    });

    test('a deposit (advance) is excluded from all three cards', () {
      final bills = [
        _bill(totalAmount: 300, isCredit: false, transactionType: 'deposit'),
      ];

      final summary = computeReportsSalesSummary(bills);

      expect(summary.cashTotal, 0);
      expect(summary.creditTotal, 0);
      expect(summary.salesCount, 0);
    });

    test('a cash_loan is excluded from all three cards', () {
      final bills = [
        _bill(totalAmount: 250, isCredit: false, transactionType: 'cash_loan'),
      ];

      final summary = computeReportsSalesSummary(bills);

      expect(summary.cashTotal, 0);
      expect(summary.creditTotal, 0);
      expect(summary.salesCount, 0);
    });

    test('a plain cash sale still counts toward नकद बिक्री / कुल बिक्री', () {
      final bills = [
        _bill(totalAmount: 500, isCredit: false, transactionType: 'sale'),
      ];

      final summary = computeReportsSalesSummary(bills);

      expect(summary.cashTotal, 500);
      expect(summary.creditTotal, 0);
      expect(summary.cashCount, 1);
      expect(summary.salesCount, 1);
    });

    test('a plain credit sale still counts toward उधार बिक्री / कुल बिक्री',
        () {
      final bills = [
        _bill(totalAmount: 1000, isCredit: true, transactionType: 'credit'),
      ];

      final summary = computeReportsSalesSummary(bills);

      expect(summary.creditTotal, 1000);
      expect(summary.cashTotal, 0);
      expect(summary.creditCount, 1);
      expect(summary.salesCount, 1);
    });

    test(
        'split bill is left alone (still whole-amount into उधार बिक्री) — '
        'open policy question, explicitly not part of this fix', () {
      final bills = [
        _bill(
          totalAmount: 2910,
          isCredit: true,
          transactionType: 'split',
          nagadAmount: 2000,
        ),
      ];

      final summary = computeReportsSalesSummary(bills);

      expect(summary.creditTotal, 2910);
      expect(summary.cashTotal, 0);
    });

    test(
        'mixed period: a payment must not inflate नकद बिक्री/कुल बिक्री '
        'alongside a real cash sale', () {
      final bills = [
        _bill(totalAmount: 500, isCredit: false, transactionType: 'sale'),
        _bill(totalAmount: 400, isCredit: false, transactionType: 'payment'),
      ];

      final summary = computeReportsSalesSummary(bills);

      expect(summary.cashTotal, 500, reason: 'payment must not count as cash sales revenue');
      expect(summary.creditTotal, 0);
      expect(summary.cashTotal + summary.creditTotal, 500);
      expect(summary.salesCount, 1);
    });
  });
}
