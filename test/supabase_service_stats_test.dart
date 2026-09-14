// Regression test for BUG-12 (`.claude/qa/BUGS.md`) — a `split`-type bill's
// FULL total_amount was being added to the 'paid' ("नकद जमा") accumulator in
// SupabaseService.fetchFilteredStats(), and never contributed anything to
// the 'credit' ("उधार दिया") accumulator, because the bucketing only checked
// resolvedType == 'credit'.
//
// fetchFilteredStats() itself hits Supabase directly, so this exercises the
// pure bucketing logic extracted into SupabaseService.bucketFilteredStats()
// (@visibleForTesting) — same pattern as models.dart's Bill.fromMap(), using
// raw row maps shaped exactly like what the `past_bills` select returns.
//
// Worked examples are taken verbatim from
// docs/features/khata-metrics-spec.md §2 Case 3 and Case 7.
import 'package:flutter_test/flutter_test.dart';
import 'package:smartdukan/services/supabase_service.dart';

void main() {
  group('SupabaseService.bucketFilteredStats (BUG-12)', () {
    test('Case 3 — ₹2000 cash / ₹910 credit split bill decomposes correctly',
        () {
      final rows = [
        {
          'total_amount': 2910,
          'is_credit': true,
          'nagad_amount': 2000,
          'transaction_type': 'split',
        },
      ];

      final result = SupabaseService.bucketFilteredStats(rows);

      // उधार दिया
      expect(result['credit'], 910);
      // नकद जमा
      expect(result['paid'], 2000);
    });

    test(
        'Case 7 — multi-transaction sequence (credit 200, split 300/nagad100, '
        'payment 150 [excluded upstream], sale 80)', () {
      // payment rows are excluded by fetchFilteredStats()'s own query filter
      // before reaching bucketFilteredStats() — not included here, mirroring
      // that contract. This test's rows are the ones that would actually
      // reach the bucketing function for this sequence.
      final rows = [
        {
          'total_amount': 200,
          'is_credit': true,
          'nagad_amount': 0,
          'transaction_type': 'credit',
        },
        {
          'total_amount': 300,
          'is_credit': true,
          'nagad_amount': 100,
          'transaction_type': 'split',
        },
        {
          'total_amount': 80,
          'is_credit': false,
          'nagad_amount': 0,
          'transaction_type': 'sale',
        },
      ];

      final result = SupabaseService.bucketFilteredStats(rows);

      // उधार दिया = 200 (credit) + 200 (split udhar: 300-100) = 400
      expect(result['credit'], 400);
      // नकद जमा = 100 (split nagad) + 80 (sale) = 180
      expect(result['paid'], 180);
    });

    test('plain sale still counts fully toward paid, not credit', () {
      final rows = [
        {
          'total_amount': 500,
          'is_credit': false,
          'nagad_amount': 0,
          'transaction_type': 'sale',
        },
      ];

      final result = SupabaseService.bucketFilteredStats(rows);

      expect(result['credit'], 0);
      expect(result['paid'], 500);
    });

    test('plain credit bill still counts fully toward credit, not paid', () {
      final rows = [
        {
          'total_amount': 1000,
          'is_credit': true,
          'nagad_amount': 0,
          'transaction_type': 'credit',
        },
      ];

      final result = SupabaseService.bucketFilteredStats(rows);

      expect(result['credit'], 1000);
      expect(result['paid'], 0);
    });

    test('split with nagad_amount greater than total_amount clamps credit '
        'portion to 0 (overpaid split edge case)', () {
      final rows = [
        {
          'total_amount': 100,
          'is_credit': true,
          'nagad_amount': 150,
          'transaction_type': 'split',
        },
      ];

      final result = SupabaseService.bucketFilteredStats(rows);

      expect(result['credit'], 0);
      expect(result['paid'], 150);
    });
  });
}
