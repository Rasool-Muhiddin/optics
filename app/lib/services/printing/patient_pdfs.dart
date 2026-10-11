import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/formatters/formatters.dart';
import '../../core/optics/powers.dart';
import '../../core/strings/app_strings.dart';
import '../../models/patients.dart';
import 'pdf_kit.dart';

/// Prescription (A5) and exam report (A4) — printable from cached data while offline.
class PatientPdfs {
  const PatientPdfs(this.kit);

  final PdfKit kit;

  List<(String, String)> _patientFields(Patient p) => [
    (AppStrings.patientName, p.fullName),
    (AppStrings.age, p.age == null ? '' : '${p.age}'),
    (AppStrings.gender, AppStrings.label(AppStrings.genders, p.gender)),
    (AppStrings.phone, p.phone),
  ];

  static String _p(String? v) => v == null ? '' : Powers.format(v);

  /// OD / OS rows: SPH CYL AXIS ADD PRISM BASE VA.
  pw.Widget rxTable(Prescription rx) {
    List<String> eye(String name, EyeRx e) => [
      name,
      _p(e.sph),
      (double.tryParse(e.cyl ?? '') ?? 0) == 0 ? '' : _p(e.cyl),
      e.axis == null ? '' : '${e.axis}°',
      _p(e.add),
      e.prism == null ? '' : e.prism!,
      e.base.isEmpty ? '' : AppStrings.label(AppStrings.prismBasesLatin, e.base),
      e.va,
    ];
    return kit.table(ltr: true, [
      ['', 'SPH', 'CYL', 'AXIS', 'ADD', 'PRISM', 'BASE', 'VA'],
      eye('OD (R)', rx.od),
      eye('OS (L)', rx.os),
    ]);
  }

  List<pw.Widget> _rxDetails(Prescription rx) => [
    pw.SizedBox(height: 6),
    kit.fields([
      ('PD', rx.pdDistance ?? ''),
      ('PD near', rx.pdNear ?? ''),
      ('PD R/L', rx.pdOd == null && rx.pdOs == null ? '' : '${rx.pdOd ?? '-'} / ${rx.pdOs ?? '-'}'),
      (AppStrings.usage, AppStrings.label(AppStrings.usages, rx.usage)),
      (AppStrings.lensDesign, AppStrings.label(AppStrings.choiceLabels, rx.lensDesign)),
      (AppStrings.lensIndex, rx.lensIndex),
      (
        AppStrings.lensCoatings,
        rx.lensCoatings.map((c) => AppStrings.label(AppStrings.choiceLabels, c)).join('، '),
      ),
      (AppStrings.frameNotes, rx.frameNotes),
      (AppStrings.prescribedBy, rx.prescribedBy),
    ]),
    if (rx.notes.isNotEmpty) ...[
      pw.SizedBox(height: 6),
      pw.Text('${AppStrings.notes}: ${rx.notes}'),
    ],
  ];

  Future<Uint8List> prescription({required Patient patient, required Prescription rx}) {
    final doc = kit.document(AppStrings.prescriptionTitle);
    doc.addPage(
      pw.Page(
        pageTheme: kit.pageTheme(PdfPageFormat.a5),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            kit.header(title: AppStrings.prescriptionTitle, date: rx.rxDate),
            kit.fields(_patientFields(patient), width: 150),
            pw.SizedBox(height: 10),
            rxTable(rx),
            ..._rxDetails(rx),
            pw.Spacer(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('${AppStrings.signature}: ..................'),
                pw.Text(Formatters.date(DateTime.now()), style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
            kit.footer(),
          ],
        ),
      ),
    );
    return doc.save();
  }

  Future<Uint8List> examReport({required Patient patient, required EyeExam exam}) {
    final doc = kit.document(AppStrings.examReportTitle);
    final rx = exam.prescription;
    doc.addPage(
      pw.MultiPage(
        pageTheme: kit.pageTheme(PdfPageFormat.a4, margin: 36),
        header: (context) => context.pageNumber == 1
            ? kit.header(title: AppStrings.examReportTitle, date: exam.examDate)
            : pw.SizedBox(),
        footer: (context) => kit.footer(),
        build: (context) => [
          kit.fields(_patientFields(patient), width: 200),
          kit.sectionTitle(AppStrings.examSection),
          kit.fields([
            (AppStrings.examinedBy, exam.examinedByName),
            (AppStrings.chiefComplaint, exam.chiefComplaint),
          ], width: 240),
          pw.SizedBox(height: 6),
          kit.table(ltr: true, [
            ['', 'VA (sc)', 'IOP (mmHg)'],
            ['OD (R)', exam.vaOd, exam.iopOd ?? ''],
            ['OS (L)', exam.vaOs, exam.iopOs ?? ''],
          ]),
          kit.sectionTitle(AppStrings.diagnosis),
          pw.Text(exam.diagnosis.isEmpty ? AppStrings.none : exam.diagnosis),
          if (exam.diagnosisDetails.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(exam.diagnosisDetails),
          ],
          if (rx != null) ...[
            kit.sectionTitle(AppStrings.prescriptionTitle),
            rxTable(rx),
            ..._rxDetails(rx),
          ],
          if (exam.notes.isNotEmpty) ...[kit.sectionTitle(AppStrings.notes), pw.Text(exam.notes)],
          pw.SizedBox(height: 30),
          pw.Text('${AppStrings.signature}: ..................'),
        ],
      ),
    );
    return doc.save();
  }
}
