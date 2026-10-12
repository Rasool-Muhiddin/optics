import 'json.dart';

/// Patient status list (must match `patients.Patient.Status`).
const patientStatuses = ['new', 'exam_done', 'lens_selected', 'in_job', 'delivered'];

class Patient {
  const Patient({
    required this.id,
    required this.fullName,
    this.birthDate,
    this.birthDateEstimated = false,
    this.age,
    this.gender = '',
    this.phone = '',
    this.address = '',
    this.notes = '',
    this.status = 'new',
    this.isArchived = false,
    this.lastExamDate,
    this.createdAt,
  });

  factory Patient.fromJson(Map<String, dynamic> j) => Patient(
    id: Json.int0(j['id']),
    fullName: Json.str(j['full_name']),
    birthDate: Json.date(j['birth_date']),
    birthDateEstimated: Json.boolean(j['birth_date_estimated']),
    age: Json.intOrNull(j['age']),
    gender: Json.str(j['gender']),
    phone: Json.str(j['phone']),
    address: Json.str(j['address']),
    notes: Json.str(j['notes']),
    status: Json.str(j['status']).isEmpty ? 'new' : Json.str(j['status']),
    isArchived: Json.boolean(j['is_archived']),
    lastExamDate: Json.date(j['last_exam_date']),
    createdAt: Json.date(j['created_at']),
  );

  final int id;
  final String fullName;
  final DateTime? birthDate;
  final bool birthDateEstimated;
  final int? age;
  final String gender;
  final String phone;
  final String address;
  final String notes;
  final String status;
  final bool isArchived;
  final DateTime? lastExamDate;
  final DateTime? createdAt;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty || fullName.toLowerCase().contains(q) || phone.contains(q);
  }
}

/// One eye of a prescription. Values are kept as the server's strings.
class EyeRx {
  const EyeRx({this.sph, this.cyl, this.axis, this.add, this.prism, this.base = '', this.va = ''});

  factory EyeRx.fromJson(Map<String, dynamic> j, String eye) => EyeRx(
    sph: Json.strOrNull(j['${eye}_sph']),
    cyl: Json.strOrNull(j['${eye}_cyl']),
    axis: Json.intOrNull(j['${eye}_axis']),
    add: Json.strOrNull(j['${eye}_add']),
    prism: Json.strOrNull(j['${eye}_prism']),
    base: Json.str(j['${eye}_base']),
    va: Json.str(j['${eye}_va']),
  );

  final String? sph;
  final String? cyl;
  final int? axis;
  final String? add;
  final String? prism;
  final String base;
  final String va;

  bool get isEmpty => sph == null && cyl == null && add == null && prism == null;

  Map<String, dynamic> toJson(String eye) => {
    '${eye}_sph': sph,
    '${eye}_cyl': cyl,
    '${eye}_axis': axis,
    '${eye}_add': add,
    '${eye}_prism': prism,
    '${eye}_base': base,
    '${eye}_va': va,
  };
}

class Prescription {
  const Prescription({
    required this.id,
    required this.patientId,
    this.patientName = '',
    this.examId,
    this.rxDate,
    this.prescribedBy = '',
    this.od = const EyeRx(),
    this.os = const EyeRx(),
    this.pdDistance,
    this.pdNear,
    this.pdOd,
    this.pdOs,
    this.usage = 'distance',
    this.lensDesign = '',
    this.lensIndex = '',
    this.lensCoatings = const [],
    this.frameNotes = '',
    this.notes = '',
    this.isVoid = false,
    this.voidReason = '',
    this.createdByName = '',
  });

  factory Prescription.fromJson(Map<String, dynamic> j) => Prescription(
    id: Json.int0(j['id']),
    patientId: Json.int0(j['patient']),
    patientName: Json.str(j['patient_name']),
    examId: Json.intOrNull(j['exam']),
    rxDate: Json.date(j['rx_date']),
    prescribedBy: Json.str(j['prescribed_by']),
    od: EyeRx.fromJson(j, 'od'),
    os: EyeRx.fromJson(j, 'os'),
    pdDistance: Json.strOrNull(j['pd_distance']),
    pdNear: Json.strOrNull(j['pd_near']),
    pdOd: Json.strOrNull(j['pd_od']),
    pdOs: Json.strOrNull(j['pd_os']),
    usage: Json.str(j['usage']).isEmpty ? 'distance' : Json.str(j['usage']),
    lensDesign: Json.str(j['lens_design']),
    lensIndex: Json.str(j['lens_index']),
    lensCoatings: [for (final c in (j['lens_coatings'] as List? ?? const [])) '$c'],
    frameNotes: Json.str(j['frame_notes']),
    notes: Json.str(j['notes']),
    isVoid: Json.boolean(j['is_void']),
    voidReason: Json.str(j['void_reason']),
    createdByName: Json.str(j['created_by_name']),
  );

  final int id;
  final int patientId;
  final String patientName;
  final int? examId;
  final DateTime? rxDate;
  final String prescribedBy;
  final EyeRx od;
  final EyeRx os;
  final String? pdDistance;
  final String? pdNear;
  final String? pdOd;
  final String? pdOs;
  final String usage;
  final String lensDesign;
  final String lensIndex;
  final List<String> lensCoatings;
  final String frameNotes;
  final String notes;
  final bool isVoid;
  final String voidReason;
  final String createdByName;

  /// Short one-line summary, e.g. `OD -2.25 -0.50×170 | OS -2.00`.
  String get summary {
    String eye(EyeRx e) {
      if (e.isEmpty) return '—';
      final b = StringBuffer(e.sph ?? '');
      final cyl = double.tryParse(e.cyl ?? '') ?? 0;
      if (cyl != 0) b.write(' ${e.cyl}×${e.axis ?? ''}');
      if (e.add != null) b.write(' ADD ${e.add}');
      return b.toString();
    }

    return 'OD ${eye(od)} | OS ${eye(os)}';
  }
}

class EyeExam {
  const EyeExam({
    required this.id,
    required this.patientId,
    this.patientName = '',
    this.examDate,
    this.examinedByName = '',
    this.examinerName = '',
    this.chiefComplaint = '',
    this.diagnosis = '',
    this.diagnosisDetails = '',
    this.vaOd = '',
    this.vaOs = '',
    this.iopOd,
    this.iopOs,
    this.notes = '',
    this.prescription,
    this.isVoid = false,
    this.voidReason = '',
  });

  factory EyeExam.fromJson(Map<String, dynamic> j) => EyeExam(
    id: Json.int0(j['id']),
    patientId: Json.int0(j['patient']),
    patientName: Json.str(j['patient_name']),
    examDate: Json.date(j['exam_date']),
    examinedByName: Json.str(j['examined_by_name']),
    examinerName: Json.str(j['examiner_name']),
    chiefComplaint: Json.str(j['chief_complaint']),
    diagnosis: Json.str(j['diagnosis']),
    diagnosisDetails: Json.str(j['diagnosis_details']),
    vaOd: Json.str(j['va_od']),
    vaOs: Json.str(j['va_os']),
    iopOd: Json.strOrNull(j['iop_od']),
    iopOs: Json.strOrNull(j['iop_os']),
    notes: Json.str(j['notes']),
    prescription: j['prescription'] is Map
        ? Prescription.fromJson(Json.map(j['prescription']))
        : null,
    isVoid: Json.boolean(j['is_void']),
    voidReason: Json.str(j['void_reason']),
  );

  final int id;
  final int patientId;
  final String patientName;
  final DateTime? examDate;
  final String examinedByName;
  final String examinerName;
  final String chiefComplaint;
  final String diagnosis;
  final String diagnosisDetails;
  final String vaOd;
  final String vaOs;
  final String? iopOd;
  final String? iopOs;
  final String notes;
  final Prescription? prescription;
  final bool isVoid;
  final String voidReason;
}
