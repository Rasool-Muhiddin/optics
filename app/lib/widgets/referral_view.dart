import 'package:flutter/material.dart';

import '../core/formatters/formatters.dart';
import '../core/strings/app_strings.dart';
import '../models/doctors.dart';
import '../models/patients.dart';
import '../services/printing/patient_pdfs.dart';
import 'common.dart';

/// The Rx of a referral as a [Prescription] (to reuse the summary / table helpers).
Prescription? referralRx(Referral r) {
  final data = r.prescription;
  if (data == null) return null;
  return Prescription.fromJson({...data, 'id': 0, 'patient': r.patientId ?? 0});
}

/// Patient snapshot + exam + Rx table of a referral (both doctor and lab side).
class ReferralView extends StatelessWidget {
  const ReferralView({super.key, required this.referral, this.showDoctor = false});

  final Referral referral;
  final bool showDoctor;

  @override
  Widget build(BuildContext context) {
    final r = referral;
    final theme = Theme.of(context);
    final rx = referralRx(r);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 16,
          children: [
            InfoTile(
              label: AppStrings.status,
              value: AppStrings.label(AppStrings.referralStatuses, r.status),
            ),
            if (showDoctor)
              InfoTile(
                label: AppStrings.doctor,
                value: [r.doctorName, r.doctorClinic].where((s) => s.isNotEmpty).join(' — '),
              ),
            if (showDoctor && r.doctorPhone.isNotEmpty)
              InfoTile(label: AppStrings.phone, value: r.doctorPhone),
            if (!showDoctor) InfoTile(label: AppStrings.chooseLab, value: r.labName),
            InfoTile(label: AppStrings.patientName, value: r.patientName),
            InfoTile(label: AppStrings.age, value: r.patientAge?.toString() ?? ''),
            InfoTile(
              label: AppStrings.gender,
              value: AppStrings.label(AppStrings.genders, r.patientGender),
            ),
            InfoTile(label: AppStrings.phone, value: r.patientPhone),
            InfoTile(label: AppStrings.examDate, value: Formatters.date(r.examDate)),
            InfoTile(label: AppStrings.chiefComplaint, value: r.chiefComplaint),
            InfoTile(label: AppStrings.diagnosis, value: r.diagnosis, width: 300),
            InfoTile(label: 'VA OD / OS', value: '${r.vaOd} / ${r.vaOs}'),
            if (r.iopOd != null || r.iopOs != null)
              InfoTile(label: 'IOP OD / OS', value: '${r.iopOd ?? '-'} / ${r.iopOs ?? '-'}'),
          ],
        ),
        if (r.diagnosisDetails.isNotEmpty)
          InfoTile(label: AppStrings.diagnosisDetails, value: r.diagnosisDetails, width: 600),
        if (rx != null) ...[
          const SizedBox(height: 8),
          Text(AppStrings.prescriptionTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          RxTableView(rx: rx),
          Wrap(
            spacing: 16,
            children: [
              if (rx.pdDistance != null)
                InfoTile(label: AppStrings.pdDistance, value: rx.pdDistance!),
              if (rx.pdNear != null) InfoTile(label: AppStrings.pdNear, value: rx.pdNear!),
              InfoTile(
                label: AppStrings.usage,
                value: AppStrings.label(AppStrings.usages, rx.usage),
              ),
              if (rx.lensDesign.isNotEmpty)
                InfoTile(
                  label: AppStrings.lensDesign,
                  value: AppStrings.label(AppStrings.choiceLabels, rx.lensDesign),
                ),
              if (rx.lensIndex.isNotEmpty)
                InfoTile(label: AppStrings.lensIndex, value: rx.lensIndex),
              if (rx.lensCoatings.isNotEmpty)
                InfoTile(
                  label: AppStrings.lensCoatings,
                  value: rx.lensCoatings
                      .map((c) => AppStrings.label(AppStrings.choiceLabels, c))
                      .join('، '),
                ),
            ],
          ),
        ],
        if (r.notes.isNotEmpty) InfoTile(label: AppStrings.doctorNote, value: r.notes, width: 600),
        if (r.rejectReason.isNotEmpty)
          InfoTile(label: AppStrings.rejectReason, value: r.rejectReason, width: 600),
      ],
    );
  }
}

/// OD/OS table of a prescription, exactly as entered (same cells as the printed Rx).
class RxTableView extends StatelessWidget {
  const RxTableView({super.key, required this.rx});

  final Prescription rx;

  @override
  Widget build(BuildContext context) {
    final rows = PatientPdfs.rxRows(rx);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 32,
          dataRowMinHeight: 32,
          dataRowMaxHeight: 36,
          columns: [for (final h in rows.first) DataColumn(label: Text(h))],
          rows: [
            for (final row in rows.skip(1))
              DataRow(cells: [for (final c in row) DataCell(Text(c))]),
          ],
        ),
      ),
    );
  }
}
