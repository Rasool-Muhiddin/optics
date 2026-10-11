import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/formatters/formatters.dart';
import '../../core/strings/app_strings.dart';
import '../../models/sales.dart';
import 'pdf_kit.dart';

/// Invoice paper sizes offered when printing.
enum InvoicePaper {
  a4(PdfPageFormat.a4),
  a5(PdfPageFormat.a5),
  thermal80(PdfPageFormat.roll80);

  const InvoicePaper(this.format);

  final PdfPageFormat format;
}

/// Invoice as A4 / A5 (table layout) or 80 mm thermal roll (compact layout).
class InvoicePdf {
  const InvoicePdf(this.kit);

  final PdfKit kit;

  String _m(String v) => Formatters.money(v, currency: AppStrings.currencyIqd);

  List<(String, String)> _totals(Invoice inv) => [
    (AppStrings.subtotal, _m(inv.subtotal)),
    if ((double.tryParse(inv.discountTotal) ?? 0) > 0) (AppStrings.discount, _m(inv.discountTotal)),
    (AppStrings.total, _m(inv.total)),
    (AppStrings.paid, _m(inv.paid)),
    if (inv.hasBalance) (AppStrings.balance, _m(inv.balance)),
  ];

  String _title(Invoice inv) =>
      '${AppStrings.invoice} #${inv.number}${inv.isCancelled ? ' — ${AppStrings.cancelled}' : ''}';

  Future<Uint8List> build(Invoice inv, InvoicePaper paper) =>
      paper == InvoicePaper.thermal80 ? _thermal(inv) : _page(inv, paper.format);

  Future<Uint8List> _page(Invoice inv, PdfPageFormat format) {
    final doc = kit.document(_title(inv));
    doc.addPage(
      pw.MultiPage(
        pageTheme: kit.pageTheme(format, margin: format == PdfPageFormat.a5 ? 24 : 36),
        header: (context) => context.pageNumber == 1
            ? kit.header(title: _title(inv), date: inv.createdAt)
            : pw.SizedBox(),
        footer: (context) => kit.footer(),
        build: (context) => [
          kit.fields([
            (AppStrings.customer, inv.customerLabel),
            (AppStrings.phone, inv.customerPhone),
            (AppStrings.paymentType, AppStrings.label(AppStrings.paymentTypes, inv.paymentType)),
            (AppStrings.cashier, inv.cashierName),
          ], width: 200),
          pw.SizedBox(height: 10),
          kit.table(
            [
              [
                '#',
                AppStrings.item,
                AppStrings.quantity,
                AppStrings.unitPrice,
                AppStrings.discount,
                AppStrings.lineTotal,
              ],
              for (var i = 0; i < inv.lines.length; i++)
                [
                  '${i + 1}',
                  inv.lines[i].description,
                  '${inv.lines[i].qty}',
                  _m(inv.lines[i].unitPrice),
                  (double.tryParse(inv.lines[i].discount) ?? 0) > 0
                      ? _m(inv.lines[i].discount)
                      : '',
                  _m(inv.lines[i].lineTotal),
                ],
            ],
            widths: const {0: pw.FixedColumnWidth(22), 1: pw.FlexColumnWidth(4)},
          ),
          pw.SizedBox(height: 8),
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.SizedBox(
              width: 220,
              child: pw.Column(
                children: [
                  for (final (label, value) in _totals(inv))
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(label, style: pw.TextStyle(font: kit.bold)),
                        pw.Text(value),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (inv.payments.any((p) => !p.isVoid)) ...[
            kit.sectionTitle(AppStrings.payments),
            kit.table([
              [AppStrings.date, AppStrings.paymentMethod, AppStrings.amount],
              for (final p in inv.payments.where((p) => !p.isVoid))
                [
                  Formatters.dateTime(p.paidAt),
                  AppStrings.label(AppStrings.paymentMethods, p.method),
                  _m(p.amount),
                ],
            ]),
          ],
          if (inv.notes.isNotEmpty) ...[pw.SizedBox(height: 8), pw.Text(inv.notes)],
        ],
      ),
    );
    return doc.save();
  }

  /// 80 mm roll: name/qty/total stacked per line, totals at the bottom.
  Future<Uint8List> _thermal(Invoice inv) {
    final doc = kit.document(_title(inv));
    const small = pw.TextStyle(fontSize: 7);
    doc.addPage(
      pw.Page(
        pageTheme: kit.pageTheme(PdfPageFormat.roll80, margin: 8),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            kit.header(title: _title(inv), date: inv.createdAt, compact: true),
            if (inv.customerLabel.isNotEmpty)
              pw.Text('${AppStrings.customer}: ${inv.customerLabel}'),
            pw.Divider(thickness: 0.5),
            for (final l in inv.lines) ...[
              pw.Text(l.description),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('${l.qty} × ${_m(l.unitPrice)}', style: small),
                  pw.Text(_m(l.lineTotal)),
                ],
              ),
              if ((double.tryParse(l.discount) ?? 0) > 0)
                pw.Text('${AppStrings.discount}: ${_m(l.discount)}', style: small),
              pw.SizedBox(height: 3),
            ],
            pw.Divider(thickness: 0.5),
            for (final (label, value) in _totals(inv))
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(label, style: pw.TextStyle(font: kit.bold)),
                  pw.Text(value),
                ],
              ),
            pw.SizedBox(height: 6),
            pw.Text(
              '${AppStrings.paymentType}: ${AppStrings.label(AppStrings.paymentTypes, inv.paymentType)}',
              style: small,
            ),
            if (inv.cashierName.isNotEmpty)
              pw.Text('${AppStrings.cashier}: ${inv.cashierName}', style: small),
            kit.footer(),
          ],
        ),
      ),
    );
    return doc.save();
  }
}
