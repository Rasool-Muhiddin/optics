"""
Doctor ↔ lab linking and referral rules. A lab takes part only while it is active, has a
valid license and its plan includes `doctor_linking`.
"""

from django.core.exceptions import ObjectDoesNotExist
from django.db import transaction
from django.utils import timezone
from rest_framework import exceptions

from apps.core.codes import normalize_link_code
from apps.core.exceptions import APIError
from apps.labs.models import Lab
from apps.patients.models import EyeExam, Patient, Prescription

from .models import DoctorLabLink, DoctorProfile, Referral

FEATURE = "doctor_linking"


def check_lab_available(lab):
    """The lab can link / receive referrals (active, valid license, plan feature)."""
    try:
        license_ = lab.license
    except ObjectDoesNotExist:
        license_ = None
    if not lab.is_active or license_ is None or not license_.is_valid():
        raise APIError("This lab is not available.", code="lab_unavailable")
    if not license_.plan.has_feature(FEATURE):
        raise exceptions.PermissionDenied("The lab's plan does not include doctor linking.", code="feature_not_in_plan")


def _request(link, side):
    """(Re)opens a link request from `side`; a pending request from the other side is accepted."""
    now = timezone.now()
    if link.status == DoctorLabLink.Status.ACCEPTED:
        raise APIError("Already linked.", code="already_linked")
    if link.status == DoctorLabLink.Status.PENDING:
        if link.requested_by == side:
            raise APIError("A request is already pending.", code="already_requested")
        link.status, link.responded_at = DoctorLabLink.Status.ACCEPTED, now  # both sides asked
    else:
        link.status, link.requested_by, link.requested_at, link.responded_at = (
            DoctorLabLink.Status.PENDING, side, now, None
        )
    link.save()
    return link


@transaction.atomic
def doctor_requests_link(*, doctor, lab_code, note=""):
    lab = Lab.objects.filter(doctor_link_code=normalize_link_code(lab_code)).first()
    if lab is None:
        raise APIError("No lab with this code.", code="invalid_link_code")
    check_lab_available(lab)
    link, created = DoctorLabLink.objects.select_for_update().get_or_create(
        lab=lab, doctor=doctor,
        defaults={"requested_by": DoctorLabLink.Side.DOCTOR, "note": note},
    )
    return link if created else _request(link, DoctorLabLink.Side.DOCTOR)


@transaction.atomic
def lab_requests_link(*, lab, doctor_code, note=""):
    doctor = DoctorProfile.objects.filter(link_code=normalize_link_code(doctor_code), is_active=True).first()
    if doctor is None:
        raise APIError("No doctor with this code.", code="invalid_link_code")
    link, created = DoctorLabLink.objects.select_for_update().get_or_create(
        lab=lab, doctor=doctor,
        defaults={"requested_by": DoctorLabLink.Side.LAB, "note": note},
    )
    return link if created else _request(link, DoctorLabLink.Side.LAB)


@transaction.atomic
def respond(*, link, side, accept):
    """Only the side that did *not* ask may accept or reject a pending request."""
    link = DoctorLabLink.objects.select_for_update().get(pk=link.pk)
    if link.status != DoctorLabLink.Status.PENDING:
        raise APIError("This request is not pending.", code="invalid_transition")
    if link.requested_by == side:
        raise APIError("The other side must answer this request.", code="cannot_answer_own_request")
    if accept and side == DoctorLabLink.Side.DOCTOR:
        check_lab_available(link.lab)
    link.status = DoctorLabLink.Status.ACCEPTED if accept else DoctorLabLink.Status.REJECTED
    link.responded_at = timezone.now()
    link.save(update_fields=["status", "responded_at", "updated_at"])
    return link


@transaction.atomic
def revoke(*, link):
    """Either side ends a link (or withdraws a pending request). Past referrals stay."""
    link = DoctorLabLink.objects.select_for_update().get(pk=link.pk)
    if link.status not in (DoctorLabLink.Status.ACCEPTED, DoctorLabLink.Status.PENDING):
        raise APIError("This link is not active.", code="invalid_transition")
    link.status = DoctorLabLink.Status.REVOKED
    link.responded_at = timezone.now()
    link.save(update_fields=["status", "responded_at", "updated_at"])
    return link


def create_referral(*, doctor, lab, data):
    if not DoctorLabLink.objects.filter(doctor=doctor, lab=lab, status=DoctorLabLink.Status.ACCEPTED).exists():
        raise APIError("You are not linked to this lab.", code="not_linked")
    check_lab_available(lab)
    return Referral.objects.create(lab=lab, doctor=doctor, **data)


def _lock(referral):
    return Referral.objects.select_for_update().get(pk=referral.pk)


def _require(referral, statuses):
    if referral.status not in statuses:
        raise APIError(f"Not allowed while the referral is {referral.status}.", code="invalid_transition")


@transaction.atomic
def mark_received(*, referral, user):
    referral = _lock(referral)
    _require(referral, (Referral.Status.SENT,))
    referral.status, referral.received_at, referral.handled_by = Referral.Status.RECEIVED, timezone.now(), user
    referral.save(update_fields=["status", "received_at", "handled_by", "updated_at"])
    return referral


@transaction.atomic
def accept(*, referral, user, patient=None):
    """
    Creates (or links to `patient`) the lab's Patient, then an EyeExam (examiner = the doctor)
    and its Prescription from the referral, in one transaction.
    """
    referral = _lock(referral)
    _require(referral, Referral.OPEN)
    lab, doctor = referral.lab, referral.doctor
    now = timezone.now()
    if patient is None:
        patient = Patient.objects.create(
            lab=lab,
            full_name=referral.patient_name,
            birth_date=Patient.birth_date_for_age(referral.patient_age) if referral.patient_age is not None else None,
            birth_date_estimated=referral.patient_age is not None,
            gender=referral.patient_gender if referral.patient_gender in Patient.Gender.values else "",
            phone=referral.patient_phone,
            created_by=user,
        )
    elif patient.lab_id != lab.id:
        raise APIError("Patient not found.", code="not_found")
    examiner = f"د. {doctor.full_name}"
    exam = EyeExam.objects.create(
        lab=lab, patient=patient, exam_date=referral.exam_date, examiner_name=examiner,
        chief_complaint=referral.chief_complaint, diagnosis=referral.diagnosis,
        diagnosis_details=referral.diagnosis_details, va_od=referral.va_od, va_os=referral.va_os,
        iop_od=referral.iop_od, iop_os=referral.iop_os, notes=referral.notes, created_by=user,
    )
    if referral.prescription_data:
        Prescription.objects.create(
            lab=lab, patient=patient, exam=exam, rx_date=referral.exam_date, prescribed_by=examiner,
            created_by=user, **referral.prescription_data,
        )
    order = [s for s, _ in Patient.Status.choices]
    if order.index(patient.status) < order.index(Patient.Status.EXAM_DONE):
        patient.status = Patient.Status.EXAM_DONE
        patient.save(update_fields=["status", "updated_at"])
    referral.status = Referral.Status.IN_PROGRESS
    referral.received_at = referral.received_at or now
    referral.accepted_at = now
    referral.handled_by = user
    referral.patient = patient
    referral.exam = exam
    referral.save()
    return referral


@transaction.atomic
def reject(*, referral, user, reason):
    referral = _lock(referral)
    _require(referral, Referral.OPEN)
    referral.status, referral.rejected_at = Referral.Status.REJECTED, timezone.now()
    referral.reject_reason, referral.handled_by = reason, user
    referral.save(update_fields=["status", "rejected_at", "reject_reason", "handled_by", "updated_at"])
    return referral


@transaction.atomic
def complete(*, referral, user):
    referral = _lock(referral)
    _require(referral, (Referral.Status.IN_PROGRESS,))
    referral.status, referral.completed_at = Referral.Status.COMPLETED, timezone.now()
    referral.save(update_fields=["status", "completed_at", "updated_at"])
    return referral
