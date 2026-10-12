import 'json.dart';
import 'session.dart';

/// The logged-in doctor (`desktop/doctor-login/`, `doctor/me/`). Doctors have no lab.
class DoctorSession {
  const DoctorSession({required this.user, required this.doctor, required this.raw});

  factory DoctorSession.fromJson(Map<String, dynamic> json) => DoctorSession(
    user: SessionUser.fromJson(Json.map(json['user'])),
    doctor: DoctorInfo.fromJson(Json.map(json['doctor'])),
    raw: json,
  );

  final SessionUser user;
  final DoctorInfo doctor;

  /// Server JSON, kept so the session can be restored from disk while offline.
  final Map<String, dynamic> raw;

  /// Stored session JSON belongs to a doctor (vs. a lab member).
  static bool isDoctorJson(Map<String, dynamic>? json) => json?['role'] == 'doctor';
}

class DoctorInfo {
  const DoctorInfo({
    required this.id,
    required this.fullName,
    this.specialty = '',
    this.clinicName = '',
    this.phone = '',
    this.linkCode = '',
  });

  factory DoctorInfo.fromJson(Map<String, dynamic> j) => DoctorInfo(
    id: Json.int0(j['id']),
    fullName: Json.str(j['full_name']),
    specialty: Json.str(j['specialty']),
    clinicName: Json.str(j['clinic_name']),
    phone: Json.str(j['phone']),
    linkCode: Json.str(j['link_code']),
  );

  final int id;
  final String fullName;
  final String specialty;
  final String clinicName;
  final String phone;
  final String linkCode;
}

/// Link statuses (must match `doctors.DoctorLabLink.Status`).
class LinkStatuses {
  const LinkStatuses._();

  static const pending = 'pending';
  static const accepted = 'accepted';
  static const rejected = 'rejected';
  static const revoked = 'revoked';
}

/// A doctor ↔ lab link, as either side sees it (the other side's public details).
class DoctorLink {
  const DoctorLink({
    required this.id,
    required this.status,
    required this.requestedBy,
    this.otherName = '',
    this.otherDetails = '',
    this.otherPhone = '',
    this.requestedAt,
    this.note = '',
    this.labId,
  });

  /// Doctor side: the other party is a lab.
  factory DoctorLink.fromDoctorJson(Map<String, dynamic> j) => DoctorLink(
    id: Json.int0(j['id']),
    status: Json.str(j['status']),
    requestedBy: Json.str(j['requested_by']),
    otherName: Json.str(j['lab_name']),
    otherDetails: Json.str(j['lab_address']),
    otherPhone: Json.str(j['lab_phone']),
    requestedAt: Json.date(j['requested_at']),
    note: Json.str(j['note']),
    labId: Json.intOrNull(j['lab']),
  );

  /// Lab side: the other party is a doctor.
  factory DoctorLink.fromLabJson(Map<String, dynamic> j) => DoctorLink(
    id: Json.int0(j['id']),
    status: Json.str(j['status']),
    requestedBy: Json.str(j['requested_by']),
    otherName: Json.str(j['doctor_name']),
    otherDetails: [
      Json.str(j['doctor_specialty']),
      Json.str(j['doctor_clinic']),
    ].where((s) => s.isNotEmpty).join(' — '),
    otherPhone: Json.str(j['doctor_phone']),
    requestedAt: Json.date(j['requested_at']),
    note: Json.str(j['note']),
  );

  final int id;
  final String status;

  /// `doctor` | `lab`.
  final String requestedBy;
  final String otherName;
  final String otherDetails;
  final String otherPhone;
  final DateTime? requestedAt;
  final String note;
  final int? labId;

  /// [side] (`doctor` / `lab`) may accept or reject: the request came from the other side.
  bool canAnswer(String side) => status == LinkStatuses.pending && requestedBy != side;
  bool get canRevoke => status == LinkStatuses.accepted || status == LinkStatuses.pending;
}

/// Referral statuses (must match `doctors.Referral.Status`).
class ReferralStatuses {
  const ReferralStatuses._();

  static const sent = 'sent';
  static const received = 'received';
  static const inProgress = 'in_progress';
  static const completed = 'completed';
  static const rejected = 'rejected';

  static const open = [sent, received];
  static const all = [sent, received, inProgress, completed, rejected];
}

class Referral {
  const Referral({
    required this.id,
    required this.status,
    required this.patientName,
    this.labId,
    this.labName = '',
    this.patientAge,
    this.patientGender = '',
    this.patientPhone = '',
    this.examDate,
    this.chiefComplaint = '',
    this.diagnosis = '',
    this.diagnosisDetails = '',
    this.vaOd = '',
    this.vaOs = '',
    this.iopOd,
    this.iopOs,
    this.prescription,
    this.notes = '',
    this.rejectReason = '',
    this.createdAt,
    this.doctorName = '',
    this.doctorClinic = '',
    this.doctorPhone = '',
    this.patientId,
    this.patientFileName = '',
    this.handledByName = '',
  });

  factory Referral.fromJson(Map<String, dynamic> j) => Referral(
    id: Json.int0(j['id']),
    status: Json.str(j['status']),
    patientName: Json.str(j['patient_name']),
    labId: Json.intOrNull(j['lab']),
    labName: Json.str(j['lab_name']),
    patientAge: Json.intOrNull(j['patient_age']),
    patientGender: Json.str(j['patient_gender']),
    patientPhone: Json.str(j['patient_phone']),
    examDate: Json.date(j['exam_date']),
    chiefComplaint: Json.str(j['chief_complaint']),
    diagnosis: Json.str(j['diagnosis']),
    diagnosisDetails: Json.str(j['diagnosis_details']),
    vaOd: Json.str(j['va_od']),
    vaOs: Json.str(j['va_os']),
    iopOd: Json.decimal(j['iop_od']),
    iopOs: Json.decimal(j['iop_os']),
    prescription: j['prescription'] is Map ? Json.map(j['prescription']) : null,
    notes: Json.str(j['notes']),
    rejectReason: Json.str(j['reject_reason']),
    createdAt: Json.date(j['created_at']),
    doctorName: Json.str(j['doctor_name']),
    doctorClinic: Json.str(j['doctor_clinic']),
    doctorPhone: Json.str(j['doctor_phone']),
    patientId: Json.intOrNull(j['patient']),
    patientFileName: Json.str(j['patient_file_name']),
    handledByName: Json.str(j['handled_by_name']),
  );

  final int id;
  final String status;
  final String patientName;
  final int? labId;
  final String labName;
  final int? patientAge;
  final String patientGender;
  final String patientPhone;
  final DateTime? examDate;
  final String chiefComplaint;
  final String diagnosis;
  final String diagnosisDetails;
  final String vaOd;
  final String vaOs;
  final String? iopOd;
  final String? iopOs;

  /// Rx fields as entered by the doctor (`od_sph`…), or null.
  final Map<String, dynamic>? prescription;
  final String notes;
  final String rejectReason;
  final DateTime? createdAt;

  // Lab side only.
  final String doctorName;
  final String doctorClinic;
  final String doctorPhone;
  final int? patientId;
  final String patientFileName;
  final String handledByName;

  bool get isOpen => ReferralStatuses.open.contains(status);
}
