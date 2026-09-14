// Smoke test + generation-latency measurement for the whole-receipt
// rasterization fix (BUG-6 / DECISIONS.md D10,
// .claude/records/2026-09-13-devanagari-pdf-fix.md).
//
// This confirms `buildBillPdfBytes` runs end-to-end without throwing on
// real conjunct-bearing Devanagari text (the PM's Success Criterion #7) and
// reports a real generation-time measurement (Success Criterion #10) using
// `flutter_test`'s real `TestWidgetsFlutterBinding` — real Skia rendering,
// not a mock, per the same precedent as `test/design_system_test.dart`.
//
// `tester.runAsync` is required here: `RenderRepaintBoundary.toImage()`
// completes via a real engine/raster-thread callback, which the default
// widget-test binding's `FakeAsync` zone cannot resolve on its own — this
// is a test-environment fact (documented by `runAsync` itself), not a
// workaround for a flaw in `_captureWidgetAsPng` (bill_pdf.dart), which
// runs unmodified in a live app.
//
// What this test CANNOT do (see the task record's Success Criteria):
// confirm the glyphs actually look right to a human. That still requires
// an on-device visual check — this only proves generation completes,
// produces a plausible PDF, and measures how long it took.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartdukan/models/models.dart';
import 'package:smartdukan/utils/bill_pdf.dart';

List<BillItem> _items(int count) {
  // Real conjunct-bearing / matra-heavy names (क्ष, त्र, ज्ञ, and the
  // original बिल/बलि matra-reordering case), not just synthetic strings.
  const names = [
    'क्षारीय साबुन', // क्ष
    'त्रिफला चूर्ण', // त्र
    'ज्ञान चाय पत्ती', // ज्ञ
    'बिस्किट', // U+093F pre-base matra case
    'Maggi Noodles', // pure-Latin, no-regression case (Criterion #9)
  ];
  return List.generate(
    count,
    (i) => BillItem(
      itemName: names[i % names.length],
      quantity: (i % 3) + 1,
      pricePerUnit: 25.5,
      itemTotal: ((i % 3) + 1) * 25.5,
      stockRemaining: 10,
      currentStock: 10,
      unit: i.isEven ? 'किलो' : 'पैकेट',
    ),
  );
}

Future<BuildContext> _pumpHostAndGetContext(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) {
      ctx = context;
      return const Scaffold(body: SizedBox());
    }),
  ));
  await tester.pumpAndSettle();
  return ctx;
}

void main() {
  testWidgets(
    'buildBillPdfBytes: typical bill (5 items) — completes, measures latency',
    (tester) async {
      final context = await _pumpHostAndGetContext(tester);

      late Uint8List bytes;
      final stopwatch = Stopwatch()..start();
      await tester.runAsync(() async {
        bytes = await buildBillPdfBytes(
          context: context,
          items: _items(5),
          customerName: 'श्री रामेश्वर क्षेत्रीय', // conjunct-bearing customer name
          isCredit: true,
          subTotal: 200,
          discount: 10,
          grandTotal: 190,
          shopName: 'क्षितिज जनरल स्टोर',
        );
      });
      stopwatch.stop();

      expect(bytes, isNotEmpty);
      // A real PDF starts with the "%PDF-" magic bytes.
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

      // ignore: avoid_print
      print(
        '[bill_pdf_test] 5-item bill: ${stopwatch.elapsedMilliseconds}ms, '
        '${bytes.length} bytes',
      );
    },
  );

  testWidgets(
    'buildBillPdfBytes: large bill (25 items) — completes, measures latency',
    (tester) async {
      final context = await _pumpHostAndGetContext(tester);

      late Uint8List bytes;
      final stopwatch = Stopwatch()..start();
      await tester.runAsync(() async {
        bytes = await buildBillPdfBytes(
          context: context,
          items: _items(25),
          customerName: 'Ramesh Kumar', // pure-Latin, no-regression case
          isCredit: false,
          subTotal: 900,
          discount: 0,
          grandTotal: 900,
          shopName: '', // exercises the "आपकी दुकान" fallback path
        );
      });
      stopwatch.stop();

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

      // ignore: avoid_print
      print(
        '[bill_pdf_test] 25-item bill: ${stopwatch.elapsedMilliseconds}ms, '
        '${bytes.length} bytes',
      );
    },
  );
}
