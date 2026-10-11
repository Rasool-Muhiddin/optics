import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/formatters/formatters.dart';
import '../../core/strings/app_strings.dart';
import '../../models/jobs.dart';
import 'patient_pdfs.dart';
import 'pdf_kit.dart';

/// Workshop / pickup ticket for a job: A5, or an 80 mm roll.
class JobTicketPdf {
  const JobTicketPdf(this.kit);

  final PdfKit kit;

  Future<Uint8List> build(Job job, {bool thermal = false}) {
    final doc = kit.document('${AppStrings.jobTicket} #${job.number}');
    final format = thermal ? PdfPageFormat.roll80 : PdfPageFormat.a5;
    final rx = job.prescription;
    final frame = switch (job.frameSource) {
      'customer' => '${AppStrings.frameSources['customer']} ${job.frameNotes}'.trim(),
      'none' => AppStrings.frameSources['none']!,
      _ => [job.frameName, job.frameNotes].where((s) => s.isNotEmpty).join(' — '),
    };
    final lens = [
      job.lensName,
      if (job.lensOdLabel.isNotEmpty) 'OD: ${job.lensOdLabel}',
      if (job.lensOsLabel.isNotEmpty) 'OS: ${job.lensOsLabel}',
      job.lensNotes,
    ].where((s) => s.isNotEmpty).join(' | ');
    final width = thermal ? 180.0 : 170.0;
    doc.addPage(
      pw.Page(
        pageTheme: kit.pageTheme(format, margin: thermal ? 8 : 24),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            kit.header(
              title: '${AppStrings.jobTicket} #${job.number}',
              date: job.createdAt,
              compact: thermal,
            ),
            kit.fields([
              (AppStrings.patientName, job.patientName),
              (AppStrings.phone, job.patientPhone),
              (AppStrings.promisedDate, Formatters.date(job.promisedDate)),
              (AppStrings.status, AppStrings.label(AppStrings.jobStatuses, job.status)),
              if (job.invoiceNumber != null) (AppStrings.linkedInvoice, '#${job.invoiceNumber}'),
              if (job.invoiceBalance != null && (double.tryParse(job.invoiceBalance!) ?? 0) > 0)
                (AppStrings.balance, Formatters.money(job.invoiceBalance)),
            ], width: width),
            pw.SizedBox(height: 6),
            kit.fields([
              (AppStrings.frame, frame),
              (AppStrings.lens, lens),
            ], width: thermal ? 180 : 360),
            if (rx != null) ...[
              kit.sectionTitle(AppStrings.prescriptionTitle),
              PatientPdfs(kit).rxTable(rx),
              pw.SizedBox(height: 4),
              kit.fields([
                ('PD', rx.pdDistance ?? ''),
                ('PD near', rx.pdNear ?? ''),
                (
                  'PD R/L',
                  rx.pdOd == null && rx.pdOs == null ? '' : '${rx.pdOd ?? '-'} / ${rx.pdOs ?? '-'}',
                ),
              ], width: thermal ? 180 : 110),
            ],
            if (job.notes.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Text('${AppStrings.notes}: ${job.notes}'),
            ],
            pw.SizedBox(height: 16),
            pw.Text('${AppStrings.customerSignature}: ..................'),
            kit.footer(),
          ],
        ),
      ),
    );
    return doc.save();
  }
}
