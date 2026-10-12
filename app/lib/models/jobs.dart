import 'json.dart';
import 'patients.dart';

/// Job lifecycle (must match `jobs.Job.Status` / `Job.TRANSITIONS`).
class JobStatuses {
  const JobStatuses._();

  static const pending = 'pending';
  static const lensOrdered = 'lens_ordered';
  static const inWorkshop = 'in_workshop';
  static const ready = 'ready';
  static const delivered = 'delivered';
  static const cancelled = 'cancelled';

  /// Board columns, in order.
  static const board = [pending, lensOrdered, inWorkshop, ready, delivered];

  static const transitions = {
    pending: [lensOrdered, inWorkshop, ready, cancelled],
    lensOrdered: [pending, inWorkshop, ready, cancelled],
    inWorkshop: [lensOrdered, ready, cancelled],
    ready: [inWorkshop, delivered, cancelled],
    delivered: <String>[],
    cancelled: <String>[],
  };

  /// The usual "move forward" step from each status.
  static const next = {
    pending: inWorkshop,
    lensOrdered: inWorkshop,
    inWorkshop: ready,
    ready: delivered,
  };

  static bool isFinal(String s) => s == delivered || s == cancelled;
}

class JobStatusLog {
  const JobStatusLog({
    required this.fromStatus,
    required this.toStatus,
    this.note = '',
    this.changedByName = '',
    this.createdAt,
  });

  factory JobStatusLog.fromJson(Map<String, dynamic> j) => JobStatusLog(
    fromStatus: Json.str(j['from_status']),
    toStatus: Json.str(j['to_status']),
    note: Json.str(j['note']),
    changedByName: Json.str(j['changed_by_name']),
    createdAt: Json.date(j['created_at']),
  );

  final String fromStatus;
  final String toStatus;
  final String note;
  final String changedByName;
  final DateTime? createdAt;
}

class Job {
  const Job({
    required this.id,
    required this.number,
    required this.patientId,
    this.patientName = '',
    this.patientPhone = '',
    this.prescriptionId,
    this.prescription,
    this.invoiceId,
    this.invoiceNumber,
    this.invoiceBalance,
    this.frameSource = 'lab',
    this.frameId,
    this.frameName = '',
    this.frameNotes = '',
    this.lensId,
    this.lensName = '',
    this.lensOdId,
    this.lensOdLabel = '',
    this.lensOsId,
    this.lensOsLabel = '',
    this.lensNotes = '',
    this.status = JobStatuses.pending,
    this.promisedDate,
    this.isOverdue = false,
    this.deliveredAt,
    this.notes = '',
    this.logs = const [],
    this.createdByName = '',
    this.createdAt,
  });

  factory Job.fromJson(Map<String, dynamic> j) => Job(
    id: Json.int0(j['id']),
    number: Json.int0(j['number']),
    patientId: Json.int0(j['patient']),
    patientName: Json.str(j['patient_name']),
    patientPhone: Json.str(j['patient_phone']),
    prescriptionId: Json.intOrNull(j['prescription']),
    prescription: j['prescription_detail'] is Map
        ? Prescription.fromJson(Json.map(j['prescription_detail']))
        : null,
    invoiceId: Json.intOrNull(j['invoice']),
    invoiceNumber: Json.intOrNull(j['invoice_number']),
    invoiceBalance: Json.decimal(j['invoice_balance']),
    frameSource: Json.str(j['frame_source']).isEmpty ? 'lab' : Json.str(j['frame_source']),
    frameId: Json.intOrNull(j['frame']),
    frameName: Json.str(j['frame_name']),
    frameNotes: Json.str(j['frame_notes']),
    lensId: Json.intOrNull(j['lens']),
    lensName: Json.str(j['lens_name']),
    lensOdId: Json.intOrNull(j['lens_od']),
    lensOdLabel: Json.str(j['lens_od_label']),
    lensOsId: Json.intOrNull(j['lens_os']),
    lensOsLabel: Json.str(j['lens_os_label']),
    lensNotes: Json.str(j['lens_notes']),
    status: Json.str(j['status']),
    promisedDate: Json.date(j['promised_date']),
    isOverdue: Json.boolean(j['is_overdue']),
    deliveredAt: Json.date(j['delivered_at']),
    notes: Json.str(j['notes']),
    logs: [for (final l in Json.list(j['status_logs'])) JobStatusLog.fromJson(l)],
    createdByName: Json.str(j['created_by_name']),
    createdAt: Json.date(j['created_at']),
  );

  final int id;
  final int number;
  final int patientId;
  final String patientName;
  final String patientPhone;
  final int? prescriptionId;
  final Prescription? prescription;
  final int? invoiceId;
  final int? invoiceNumber;
  final String? invoiceBalance;
  final String frameSource;
  final int? frameId;
  final String frameName;
  final String frameNotes;
  final int? lensId;
  final String lensName;
  final int? lensOdId;
  final String lensOdLabel;
  final int? lensOsId;
  final String lensOsLabel;
  final String lensNotes;
  final String status;
  final DateTime? promisedDate;

  /// From the server (promised date passed while still pending / ordered / in workshop).
  final bool isOverdue;
  final DateTime? deliveredAt;
  final String notes;
  final List<JobStatusLog> logs;
  final String createdByName;
  final DateTime? createdAt;

  bool get isFinal => JobStatuses.isFinal(status);

  /// Offline re-evaluation of [isOverdue] (cached rows may be days old).
  bool overdueOn(DateTime today) {
    final d = promisedDate;
    if (d == null) return false;
    const active = [JobStatuses.pending, JobStatuses.lensOrdered, JobStatuses.inWorkshop];
    final day = DateTime(today.year, today.month, today.day);
    return active.contains(status) && DateTime(d.year, d.month, d.day).isBefore(day);
  }
}
