import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/formatters/formatters.dart';
import '../../core/strings/app_strings.dart';
import '../../models/session.dart';

/// Fonts + lab header shared by every printed document (works offline: no network).
class PdfKit {
  PdfKit({required this.base, required this.bold, required this.lab, this.logo});

  final pw.Font base;
  final pw.Font bold;
  final LabInfo lab;
  final Uint8List? logo;

  /// Bundled Arabic font; Latin glyphs (OD/OS, SPH…) fall back to Helvetica.
  static Future<PdfKit> load(LabInfo lab, {Uint8List? logo}) async {
    final regular = await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf');
    return PdfKit(base: pw.Font.ttf(regular), bold: pw.Font.ttf(boldData), lab: lab, logo: logo);
  }

  pw.ThemeData theme({double fontSize = 10}) {
    final t = pw.ThemeData.withFont(
      base: base,
      bold: bold,
      fontFallback: [pw.Font.helvetica(), pw.Font.helveticaBold()],
    );
    return t.copyWith(defaultTextStyle: t.defaultTextStyle.copyWith(fontSize: fontSize));
  }

  pw.Document document(String title) =>
      pw.Document(title: title, author: lab.name, creator: AppStrings.appTitle, theme: theme());

  pw.PageTheme pageTheme(PdfPageFormat format, {double margin = 28}) => pw.PageTheme(
    pageFormat: format.copyWith(
      marginLeft: margin,
      marginRight: margin,
      marginTop: margin,
      marginBottom: margin,
    ),
    textDirection: pw.TextDirection.rtl,
    theme: theme(fontSize: format.width < 300 ? 8 : 10),
  );

  /// Lab name / phone / address / print header (+ logo) and a rule.
  pw.Widget header({required String title, DateTime? date, bool compact = false}) {
    final lines = [
      if (lab.phone.isNotEmpty) lab.phone,
      if (lab.address.isNotEmpty) lab.address,
      if (lab.printHeader.isNotEmpty) lab.printHeader,
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logo != null && !compact)
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 10),
                child: pw.Image(pw.MemoryImage(logo!), width: 56, height: 56),
              ),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    lab.name,
                    style: pw.TextStyle(font: bold, fontSize: compact ? 11 : 16),
                  ),
                  for (final l in lines) pw.Text(l, style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(font: bold, fontSize: compact ? 10 : 13),
                ),
                if (date != null)
                  pw.Text(Formatters.date(date), style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ],
        ),
        pw.Divider(thickness: 1),
      ],
    );
  }

  pw.Widget footer() => lab.printFooter.isEmpty
      ? pw.SizedBox()
      : pw.Column(
          children: [
            pw.Divider(thickness: 0.5),
            pw.Text(
              lab.printFooter,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        );

  /// "Label: value" pairs laid out in a wrap.
  pw.Widget fields(List<(String, String)> pairs, {double width = 160}) => pw.Wrap(
    spacing: 12,
    runSpacing: 4,
    children: [
      for (final (label, value) in pairs)
        if (value.isNotEmpty)
          pw.SizedBox(
            width: width,
            child: pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: '$label: ',
                    style: pw.TextStyle(font: bold),
                  ),
                  pw.TextSpan(text: value),
                ],
              ),
            ),
          ),
    ],
  );

  /// Bordered table; [ltr] keeps numeric tables (Rx) left-to-right like printed Rx pads.
  pw.Widget table(
    List<List<String>> rows, {
    bool ltr = false,
    Map<int, pw.TableColumnWidth>? widths,
  }) {
    final table = pw.Table(
      border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey700),
      columnWidths: widths,
      children: [
        for (var i = 0; i < rows.length; i++)
          pw.TableRow(
            decoration: i == 0 ? const pw.BoxDecoration(color: PdfColors.grey300) : null,
            children: [
              for (final cell in rows[i])
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  child: pw.Text(
                    cell,
                    textAlign: pw.TextAlign.center,
                    style: i == 0 ? pw.TextStyle(font: bold) : null,
                  ),
                ),
            ],
          ),
      ],
    );
    return ltr ? pw.Directionality(textDirection: pw.TextDirection.ltr, child: table) : table;
  }

  pw.Widget sectionTitle(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
    child: pw.Text(text, style: pw.TextStyle(font: bold, fontSize: 11)),
  );
}
