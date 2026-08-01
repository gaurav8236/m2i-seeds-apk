import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/models.dart';
import 'devanagari.dart';

/// Single source of truth for bill PDF generation.
/// Used by both VoiceBillingScreen (new bill) and PastBillsScreen (reprint).
Future<Uint8List> buildBillPdfBytes({
  required List<BillItem> items,
  required String customerName,
  required bool isCredit,
  required double subTotal,
  required double discount,
  required double grandTotal,
  String shopName = '',
  DateTime? date,
}) async {
  final regular = await PdfGoogleFonts.notoSansRegular();
  final bold = await PdfGoogleFonts.notoSansBold();
  final devaRegular = await PdfGoogleFonts.notoSansDevanagariRegular();
  final devaBold = await PdfGoogleFonts.notoSansDevanagariBold();

  const PdfColor red = PdfColor.fromInt(0xFFDC2626);
  const PdfColor grey = PdfColor.fromInt(0xFF6B7280);
  const PdfColor black = PdfColors.black;

  // 80mm thermal receipt width
  const double pageWidth = 80 * PdfPageFormat.mm;

  final String displayShopName = shopName.isNotEmpty ? shopName : 'आपकी दुकान';

  final double headerH = 72.0;
  final double infoH = 44.0 + (customerName.isNotEmpty ? 16.0 : 0) + (isCredit ? 18.0 : 0);
  const double tblHeadH = 28.0;
  final double itemsH = items.length * 24.0;
  final double summaryH = 50.0 + (discount > 0 ? 18.0 : 0);
  const double footerH = 36.0;
  final double totalH = headerH + infoH + tblHeadH + itemsH + summaryH + footerH;

  final pageFormat = PdfPageFormat(pageWidth, totalH, marginAll: 14);

  pw.Widget dashedLine() => pw.Container(
    margin: const pw.EdgeInsets.symmetric(vertical: 5),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(width: 0.6, style: pw.BorderStyle.dashed, color: grey),
      ),
    ),
  );

  pw.TextStyle sty({required pw.Font font, double size = 10, PdfColor? color}) =>
      pw.TextStyle(font: font, fontSize: size, color: color);

  final billDate = date ?? DateTime.now();

  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: pageFormat,
    build: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [

        // ── HEADER — shopkeeper name as main title ───────────────────
        pw.Center(child: pw.Text(
          fixDevanagariMatra(displayShopName),
          style: sty(font: devaBold, size: 18, color: black),
          textAlign: pw.TextAlign.center,
        )),
        pw.SizedBox(height: 10),
        dashedLine(),

        // ── BILL INFO ────────────────────────────────────────────────
        pw.SizedBox(height: 6),
        pw.RichText(text: pw.TextSpan(children: [
          pw.TextSpan(text: fixDevanagariMatra('दिनांक: '), style: sty(font: devaBold, size: 11)),
          pw.TextSpan(text: DateFormat('d/M/yyyy, h:mm a').format(billDate), style: sty(font: regular, size: 11)),
        ])),
        if (customerName.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.RichText(text: pw.TextSpan(children: [
            pw.TextSpan(text: fixDevanagariMatra('ग्राहक: '), style: sty(font: devaBold, size: 11)),
            pw.TextSpan(text: fixDevanagariMatra(customerName), style: sty(font: devaRegular, size: 11)),
          ])),
        ],
        if (isCredit) ...[
          pw.SizedBox(height: 4),
          pw.Text(fixDevanagariMatra('** उधार बिल **'), style: sty(font: devaBold, size: 11, color: red)),
        ],
        pw.SizedBox(height: 10),

        // ── TABLE HEADER — आइटम | मात्रा | इकाई | दर | कुल ──────────
        pw.Row(children: [
          pw.Expanded(flex: 5, child: pw.Text(fixDevanagariMatra('आइटम'), style: sty(font: devaBold, size: 10))),
          pw.SizedBox(width: 32, child: pw.Text(fixDevanagariMatra('मात्रा'), textAlign: pw.TextAlign.center, style: sty(font: devaBold, size: 10))),
          pw.SizedBox(width: 30, child: pw.Text(fixDevanagariMatra('इकाई'), textAlign: pw.TextAlign.center, style: sty(font: devaBold, size: 10))),
          pw.SizedBox(width: 30, child: pw.Text(fixDevanagariMatra('दर'), textAlign: pw.TextAlign.right, style: sty(font: devaBold, size: 10))),
          pw.SizedBox(width: 34, child: pw.Text(fixDevanagariMatra('कुल'), textAlign: pw.TextAlign.right, style: sty(font: devaBold, size: 10))),
        ]),
        pw.SizedBox(height: 4),
        pw.Divider(thickness: 0.8, color: black),

        // ── ITEMS ────────────────────────────────────────────────────
        ...items.map((item) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(flex: 5, child: pw.Text(fixDevanagariMatra(item.itemName), style: sty(font: devaRegular, size: 10))),
              pw.SizedBox(width: 32, child: pw.Text(
                item.quantity % 1 == 0 ? item.quantity.toInt().toString() : item.quantity.toStringAsFixed(1),
                textAlign: pw.TextAlign.center, style: sty(font: regular, size: 10))),
              pw.SizedBox(width: 30, child: pw.Text(fixDevanagariMatra(item.unit), textAlign: pw.TextAlign.center, style: sty(font: devaRegular, size: 10))),
              pw.SizedBox(width: 30, child: pw.Text(
                '₹${item.pricePerUnit % 1 == 0 ? item.pricePerUnit.toInt() : item.pricePerUnit.toStringAsFixed(1)}',
                textAlign: pw.TextAlign.right, style: sty(font: regular, size: 10))),
              pw.SizedBox(width: 34, child: pw.Text(
                '₹${item.itemTotal % 1 == 0 ? item.itemTotal.toInt() : item.itemTotal.toStringAsFixed(0)}',
                textAlign: pw.TextAlign.right, style: sty(font: bold, size: 10))),
            ],
          ),
        )),

        pw.SizedBox(height: 4),
        dashedLine(),

        // ── SUMMARY ──────────────────────────────────────────────────
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(fixDevanagariMatra('उप-कुल राशि'), style: sty(font: devaRegular, size: 11)),
            pw.Text('₹${subTotal.toStringAsFixed(2)}', style: sty(font: regular, size: 11)),
          ],
        ),
        if (discount > 0) ...[
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(fixDevanagariMatra('छूट'), style: sty(font: devaBold, size: 11, color: red)),
              pw.Text('-₹${discount.toStringAsFixed(2)}', style: sty(font: bold, size: 11, color: red)),
            ],
          ),
        ],
        dashedLine(),

        // ── TOTAL ────────────────────────────────────────────────────
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(fixDevanagariMatra('कुल राशि'), style: sty(font: devaBold, size: 13)),
            pw.Text('₹${grandTotal.toStringAsFixed(2)}', style: sty(font: bold, size: 13)),
          ],
        ),

        pw.SizedBox(height: 14),

        // ── FOOTER ───────────────────────────────────────────────────
        pw.Center(child: pw.Text(fixDevanagariMatra('धन्यवाद! फिर पधारें।'), style: sty(font: devaRegular, size: 10, color: grey))),
        pw.SizedBox(height: 6),
        pw.Center(child: pw.Text('Powered by SmartDukan', style: sty(font: regular, size: 8, color: grey))),
      ],
    ),
  ));

  return pdf.save();
}
