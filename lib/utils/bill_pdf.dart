import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/models.dart';

/// Single source of truth for bill PDF generation.
/// Used by both VoiceBillingScreen (new bill) and PastBillsScreen (reprint).
///
/// BUG-6 / DECISIONS.md D10: `package:pdf` has no Devanagari shaping engine
/// (no GSUB conjunct substitution, no GPOS mark positioning) — no amount of
/// pre-processing the text handed to `pw.Text` can fix that structurally,
/// which is why the previous `fixDevanagariMatra()` patch kept failing on
/// new cases. This version sidesteps the gap entirely: the whole receipt is
/// built as a normal Flutter widget tree (reusing the exact `dart:ui` shaper
/// that already renders Hindi correctly everywhere else on-screen in this
/// app, e.g. `bill_card.dart`'s labels), rasterized off-screen to a single
/// PNG, and embedded as one image in a single-page PDF. There is no
/// `pw.Text`/`pw.RichText` anywhere in this file any more — nothing left
/// here that can regress into a Devanagari-specific bug again.
Future<Uint8List> buildBillPdfBytes({
  required BuildContext context,
  required List<BillItem> items,
  required String customerName,
  required bool isCredit,
  required double subTotal,
  required double discount,
  required double grandTotal,
  String shopName = '',
  DateTime? date,
}) async {
  // Success Criterion #10 (.claude/records/2026-09-13-devanagari-pdf-fix.md):
  // generation latency must be measured, not assumed, since this rasterize
  // approach does real work (off-screen layout/paint + toImage + PNG encode)
  // the old direct-vector-text path didn't. Kept as an always-on, zero-cost
  // debug log so a real on-device measurement is one `flutter run` away for
  // whoever runs QA on this, rather than needing bespoke instrumentation.
  final stopwatch = Stopwatch()..start();

  // 80mm thermal-receipt width, same physical size as before — converted
  // from PDF points (72/inch) to Flutter's logical pixels (96/inch) since
  // the receipt is now laid out as a widget, not a `pw.*` tree.
  final double pageWidthPt = 80 * PdfPageFormat.mm;
  final double logicalWidth = _ptToLogicalPx(pageWidthPt);

  final receipt = _buildReceiptWidget(
    width: logicalWidth,
    items: items,
    customerName: customerName,
    isCredit: isCredit,
    subTotal: subTotal,
    discount: discount,
    grandTotal: grandTotal,
    shopName: shopName,
    date: date ?? DateTime.now(),
  );

  final captured = await _captureWidgetAsPng(
    context: context,
    child: receipt,
    logicalWidth: logicalWidth,
    // ~285dpi-equivalent at 80mm width. Flagged by Architect for on-device
    // tuning (crispness vs. file size/generation time) — not prescribed as
    // final here.
    pixelRatio: 3.0,
  );

  final pdf = pw.Document();
  final double pageHeightPt =
      pageWidthPt * (captured.height / captured.width);
  final pdfImage = pw.MemoryImage(captured.bytes);

  pdf.addPage(pw.Page(
    // marginAll: 0 — the receipt's own padding is already baked into the
    // captured widget (see _buildReceiptWidget), not re-added here.
    pageFormat: PdfPageFormat(pageWidthPt, pageHeightPt, marginAll: 0),
    build: (ctx) => pw.Image(pdfImage, fit: pw.BoxFit.fill),
  ));

  final bytes = await pdf.save();

  stopwatch.stop();
  debugPrint(
    '[bill_pdf] whole-receipt rasterization: ${stopwatch.elapsedMilliseconds}ms '
    'for ${items.length} item(s), ${captured.width}x${captured.height}px '
    '(pixelRatio 3.0), ${bytes.length} bytes',
  );

  return bytes;
}

/// Points (`package:pdf`'s unit, 72/inch) → Flutter logical pixels (96/inch).
double _ptToLogicalPx(double points) => points * 96 / 72;

// ── Off-screen capture ──────────────────────────────────────────────────

/// Renders [child] off-screen at [logicalWidth] and rasterizes it to a PNG
/// via Flutter's own renderer — the same shaping path already proven
/// correct for this app's on-screen Hindi text. Returns the PNG bytes plus
/// its pixel dimensions (needed to size the PDF page/image correctly).
///
/// This builds a fully separate, self-contained render/element tree (its
/// own [PipelineOwner] and [RenderView], not attached to the live app's
/// widget tree at all) and drives layout/paint on it manually, rather than
/// inserting into the app's real `Overlay` and waiting on the ambient
/// [SchedulerBinding] to produce a frame. That earlier approach is the
/// common pattern for "share this widget as an image" features, but it
/// depends on a live, engine-driven frame loop — which a real running app
/// has, but `flutter_test`'s widget-test binding does not (frames there
/// only advance on an explicit `pump()`, which nothing here can reach).
/// This version has no such dependency: it works identically in a live app
/// and in a widget test, with zero risk of an on-screen flash or of
/// interfering with whatever the user is actually looking at, since the
/// tree it builds is never part of the visible app.
///
/// This is the one genuinely new mechanism in this fix; everything else in
/// `buildBillPdfBytes` is a like-for-like port of the old `pw.*` tree to
/// Flutter widgets.
Future<({Uint8List bytes, int width, int height})> _captureWidgetAsPng({
  required BuildContext context,
  required Widget child,
  required double logicalWidth,
  required double pixelRatio,
}) async {
  // Note: deliberately *not* a widget-level `RepaintBoundary` + `GlobalKey`.
  // `GlobalKey.currentContext` always looks up the ambient
  // `WidgetsBinding.instance.buildOwner`'s registry — never the detached
  // `buildOwner` created below — so it would never find an element mounted
  // here. Holding the `RenderRepaintBoundary` as a plain reference sidesteps
  // that registry entirely.
  final repaintBoundary = RenderRepaintBoundary();

  final renderView = RenderView(
    view: View.of(context),
    configuration: ViewConfiguration(
      // Tight width, loose height — the receipt sizes itself to its
      // content (item count varies), same as it did as a `pw.Column`.
      logicalConstraints: BoxConstraints.tightFor(width: logicalWidth),
    ),
    child: repaintBoundary,
  );

  final pipelineOwner = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();

  // A dedicated BuildOwner for this detached tree — deliberately not the
  // app's own, so building/laying out/painting it can never mark anything
  // in the live app dirty or vice versa.
  final buildOwner = BuildOwner(focusManager: FocusManager());

  final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
    container: repaintBoundary,
    // `Directionality` has no fallback (Text/RichText assert on it); the
    // real app provides it via MaterialApp, but this tree is detached from
    // that, so it's supplied explicitly here.
    child: Directionality(
      // Unprefixed `TextDirection` is ambiguous here: `package:intl`
      // exports its own unrelated `TextDirection` class (LTR/RTL/UNKNOWN,
      // no `.ltr`) alongside Flutter's `dart:ui` enum of the same name —
      // qualifying via the `ui.` prefix picks the right one explicitly.
      textDirection: ui.TextDirection.ltr,
      child: child,
    ),
  ).attachToRenderTree(buildOwner);

  buildOwner.buildScope(rootElement);
  buildOwner.finalizeTree();

  pipelineOwner.flushLayout();
  pipelineOwner.flushCompositingBits();
  pipelineOwner.flushPaint();

  final image = await repaintBoundary.toImage(pixelRatio: pixelRatio);
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return (
      bytes: byteData!.buffer.asUint8List(),
      width: image.width,
      height: image.height,
    );
  } finally {
    image.dispose();
  }
}

// ── Receipt widget tree — like-for-like port of the old `pw.*` layout ────

const Color _black = Colors.black;
const Color _grey = Color(0xFF6B7280);
const Color _red = Color(0xFFDC2626);

Widget _buildReceiptWidget({
  required double width,
  required List<BillItem> items,
  required String customerName,
  required bool isCredit,
  required double subTotal,
  required double discount,
  required double grandTotal,
  required String shopName,
  required DateTime date,
}) {
  final String displayShopName = shopName.isNotEmpty ? shopName : 'आपकी दुकान';

  TextStyle sty({
    double size = 10,
    FontWeight weight = FontWeight.normal,
    Color color = _black,
  }) =>
      TextStyle(
        fontSize: _ptToLogicalPx(size),
        fontWeight: weight,
        color: color,
        // No explicit fontFamily: the app's default theme font (Roboto) has
        // no Devanagari glyphs, but Skia/`dart:ui` automatically falls back
        // to the OS's Devanagari font and shapes it correctly — exactly
        // like every other Hindi label already on-screen in this app.
      );

  return Container(
    color: Colors.white,
    padding: EdgeInsets.all(_ptToLogicalPx(14)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── HEADER — shopkeeper name as main title ─────────────────────
        Center(
          child: Text(
            displayShopName,
            style: sty(size: 18, weight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
        SizedBox(height: _ptToLogicalPx(10)),
        const _DashedDivider(),

        // ── BILL INFO ────────────────────────────────────────────────
        SizedBox(height: _ptToLogicalPx(6)),
        RichText(
          text: TextSpan(children: [
            TextSpan(text: 'दिनांक: ', style: sty(size: 11, weight: FontWeight.bold)),
            TextSpan(
              text: DateFormat('d/M/yyyy, h:mm a').format(date),
              style: sty(size: 11),
            ),
          ]),
        ),
        if (customerName.isNotEmpty) ...[
          SizedBox(height: _ptToLogicalPx(4)),
          RichText(
            text: TextSpan(children: [
              TextSpan(text: 'ग्राहक: ', style: sty(size: 11, weight: FontWeight.bold)),
              TextSpan(text: customerName, style: sty(size: 11)),
            ]),
          ),
        ],
        if (isCredit) ...[
          SizedBox(height: _ptToLogicalPx(4)),
          Text('** उधार बिल **', style: sty(size: 11, weight: FontWeight.bold, color: _red)),
        ],
        SizedBox(height: _ptToLogicalPx(10)),

        // ── TABLE HEADER — आइटम | मात्रा | इकाई | दर | कुल ────────────
        Row(children: [
          Expanded(flex: 5, child: Text('आइटम', style: sty(weight: FontWeight.bold))),
          SizedBox(
            width: _ptToLogicalPx(32),
            child: Text('मात्रा', textAlign: TextAlign.center, style: sty(weight: FontWeight.bold)),
          ),
          SizedBox(
            width: _ptToLogicalPx(30),
            child: Text('इकाई', textAlign: TextAlign.center, style: sty(weight: FontWeight.bold)),
          ),
          SizedBox(
            width: _ptToLogicalPx(30),
            child: Text('दर', textAlign: TextAlign.right, style: sty(weight: FontWeight.bold)),
          ),
          SizedBox(
            width: _ptToLogicalPx(34),
            child: Text('कुल', textAlign: TextAlign.right, style: sty(weight: FontWeight.bold)),
          ),
        ]),
        SizedBox(height: _ptToLogicalPx(4)),
        Container(height: 0.8, color: _black),

        // ── ITEMS ────────────────────────────────────────────────────
        ...items.map((item) => Padding(
              padding: EdgeInsets.symmetric(vertical: _ptToLogicalPx(5)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: Text(item.itemName, style: sty())),
                  SizedBox(
                    width: _ptToLogicalPx(32),
                    child: Text(
                      item.quantity % 1 == 0
                          ? item.quantity.toInt().toString()
                          : item.quantity.toStringAsFixed(1),
                      textAlign: TextAlign.center,
                      style: sty(),
                    ),
                  ),
                  SizedBox(
                    width: _ptToLogicalPx(30),
                    child: Text(item.unit, textAlign: TextAlign.center, style: sty()),
                  ),
                  SizedBox(
                    width: _ptToLogicalPx(30),
                    child: Text(
                      '₹${item.pricePerUnit % 1 == 0 ? item.pricePerUnit.toInt() : item.pricePerUnit.toStringAsFixed(1)}',
                      textAlign: TextAlign.right,
                      style: sty(),
                    ),
                  ),
                  SizedBox(
                    width: _ptToLogicalPx(34),
                    child: Text(
                      '₹${item.itemTotal % 1 == 0 ? item.itemTotal.toInt() : item.itemTotal.toStringAsFixed(0)}',
                      textAlign: TextAlign.right,
                      style: sty(weight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            )),

        SizedBox(height: _ptToLogicalPx(4)),
        const _DashedDivider(),

        // ── SUMMARY ──────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('उप-कुल राशि', style: sty(size: 11)),
            Text('₹${subTotal.toStringAsFixed(2)}', style: sty(size: 11)),
          ],
        ),
        if (discount > 0) ...[
          SizedBox(height: _ptToLogicalPx(4)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('छूट', style: sty(size: 11, weight: FontWeight.bold, color: _red)),
              Text('-₹${discount.toStringAsFixed(2)}',
                  style: sty(size: 11, weight: FontWeight.bold, color: _red)),
            ],
          ),
        ],
        const _DashedDivider(),

        // ── TOTAL ────────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('कुल राशि', style: sty(size: 13, weight: FontWeight.bold)),
            Text('₹${grandTotal.toStringAsFixed(2)}', style: sty(size: 13, weight: FontWeight.bold)),
          ],
        ),

        SizedBox(height: _ptToLogicalPx(14)),

        // ── FOOTER ───────────────────────────────────────────────────
        Center(
          child: Text('धन्यवाद! फिर पधारें।', style: sty(color: _grey), textAlign: TextAlign.center),
        ),
        SizedBox(height: _ptToLogicalPx(6)),
        Center(
          child: Text('Powered by SmartDukan', style: sty(size: 8, color: _grey)),
        ),
      ],
    ),
  );
}

/// Dashed horizontal rule — `package:pdf`'s `BorderStyle.dashed` has no
/// Flutter-SDK equivalent, so this draws one manually. No package needed.
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: _ptToLogicalPx(5)),
      child: LayoutBuilder(
        builder: (context, constraints) => CustomPaint(
          size: Size(constraints.maxWidth, 0.6),
          painter: const _DashedLinePainter(),
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _grey
      ..strokeWidth = 0.6;
    const dashWidth = 3.0;
    const dashSpace = 2.0;
    double x = 0;
    final y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dashWidth, y), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) => false;
}
