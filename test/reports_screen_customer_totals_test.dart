// Tests for `aggregateBillsByCustomer()` — the pure roll-up behind the Reports
// screen's "ग्राहक" view (total bill amount per customer). Like BUG-13's old
// summary test, it works on `Bill` objects directly because the screen itself
// needs a live Supabase call to populate.
import 'package:flutter_test/flutter_test.dart';
import 'package:smartdukan/models/models.dart';
import 'package:smartdukan/screens/reports_screen.dart';

Bill _bill({
  required double totalAmount,
  String? customerName,
  bool isCredit = false,
  String transactionType = 'sale',
}) {
  return Bill(
    id: 'test-${DateTime.now().microsecondsSinceEpoch}-$totalAmount',
    createdAt: DateTime(2026, 9, 13),
    customerName: customerName,
    totalAmount: totalAmount,
    isCredit: isCredit,
    transactionType: transactionType,
    billDetails: const [],
  );
}

void main() {
  group('aggregateBillsByCustomer', () {
    test('sums total and counts bills per customer', () {
      final result = aggregateBillsByCustomer([
        _bill(totalAmount: 100, customerName: 'Ramesh'),
        _bill(totalAmount: 250, customerName: 'Ramesh', isCredit: true),
        _bill(totalAmount: 80, customerName: 'Sita'),
      ]);

      expect(result.length, 2);
      expect(result[0].name, 'Ramesh');
      expect(result[0].billCount, 2);
      expect(result[0].totalAmount, 350);
      expect(result[1].name, 'Sita');
      expect(result[1].billCount, 1);
      expect(result[1].totalAmount, 80);
    });

    test('sorts by total descending', () {
      final result = aggregateBillsByCustomer([
        _bill(totalAmount: 10, customerName: 'A'),
        _bill(totalAmount: 900, customerName: 'B'),
        _bill(totalAmount: 500, customerName: 'C'),
      ]);

      expect(result.map((c) => c.name), ['B', 'C', 'A']);
    });

    test('matches names case-insensitively and ignores surrounding spaces, '
        'keeping first-seen casing', () {
      final result = aggregateBillsByCustomer([
        _bill(totalAmount: 100, customerName: 'Mayank'),
        _bill(totalAmount: 50, customerName: ' mayank '),
      ]);

      expect(result.length, 1);
      expect(result.single.name, 'Mayank');
      expect(result.single.totalAmount, 150);
    });

    test('bills with no customer name are grouped as नकद ग्राहक', () {
      final result = aggregateBillsByCustomer([
        _bill(totalAmount: 40),
        _bill(totalAmount: 60, customerName: ''),
        _bill(totalAmount: 5, customerName: '   '),
      ]);

      expect(result.length, 1);
      expect(result.single.name, 'नकद ग्राहक');
      expect(result.single.billCount, 3);
      expect(result.single.totalAmount, 105);
    });

    test('payment / deposit / cash_loan rows are not counted as sales', () {
      final result = aggregateBillsByCustomer([
        _bill(totalAmount: 100, customerName: 'Ramesh'),
        _bill(
            totalAmount: 400,
            customerName: 'Ramesh',
            transactionType: 'payment'),
        _bill(
            totalAmount: 300,
            customerName: 'Ramesh',
            transactionType: 'deposit'),
        _bill(
            totalAmount: 200,
            customerName: 'Ramesh',
            transactionType: 'cash_loan'),
      ]);

      expect(result.single.billCount, 1);
      expect(result.single.totalAmount, 100);
    });

    test('a customer with only non-sale rows does not appear', () {
      final result = aggregateBillsByCustomer([
        _bill(
            totalAmount: 400, customerName: 'Sita', transactionType: 'payment'),
      ]);

      expect(result, isEmpty);
    });

    test('empty input gives an empty list', () {
      expect(aggregateBillsByCustomer([]), isEmpty);
    });
  });
}
