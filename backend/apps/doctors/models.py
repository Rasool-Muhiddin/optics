"""
Doctor accounts (independent of labs), doctor ↔ lab links and referrals (P7).

A doctor is a `User` with a `DoctorProfile` and no `LabUser` membership. Doctors and labs
find each other with short link codes (`DoctorProfile.link_code`, `Lab.doctor_link_code`);
either side may request a link, the other side accepts or rejects it, either side revokes.
"""

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.serializers.json import DjangoJSONEncoder
from django.db import models
from django.utils import timezone

from apps.core.codes import generate_link_code, normalize_link_code
from apps.core.models import LabScopedModel, TimeStampedModel


class DoctorProfile(TimeStampedModel):
    """Created by Tera in Django Admin (like labs). The user must not belong to a lab."""

    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="doctor_profile")
    full_name = models.CharField(max_length=200)
    specialty = models.CharField(max_length=150, blank=True)
    clinic_name = models.CharField(max_length=200, blank=True)
    phone = models.CharField(max_length=50, blank=True)
    address = models.CharField(max_length=300, blank=True)
    link_code = models.CharField(max_length=16, unique=True, default=generate_link_code)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["full_name", "id"]

    def __str__(self):
        return self.full_name

    def save(self, *args, **kwargs):
        self.link_code = normalize_link_code(self.link_code)
        super().save(*args, **kwargs)

    def clean(self):
        super().clean()
        if self.user_id and hasattr(self.user, "lab_membership"):
            raise ValidationError({"user": "This user is a lab member; doctors cannot belong to a lab."})


class DoctorLabLink(LabScopedModel):
    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        ACCEPTED = "accepted", "Accepted"
        REJECTED = "rejected", "Rejected"
        REVOKED = "revoked", "Revoked"

    class Side(models.TextChoices):
        DOCTOR = "doctor", "Doctor"
        LAB = "lab", "Lab"

    doctor = models.ForeignKey(DoctorProfile, on_delete=models.PROTECT, related_name="lab_links")
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.PENDING, db_index=True)
    requested_by = models.CharField(max_length=10, choices=Side.choices)
    requested_at = models.DateTimeField(default=timezone.now)
    responded_at = models.DateTimeField(null=True, blank=True)
    note = models.CharField(max_length=300, blank=True)

    class Meta:
        ordering = ["-requested_at", "-id"]
        constraints = [models.UniqueConstraint(fields=["lab", "doctor"], name="unique_doctor_lab_link")]

    def __str__(self):
        return f"{self.doctor} ↔ {self.lab} ({self.status})"


class Referral(LabScopedModel):
    """
    A doctor sends a patient (snapshot) + exam + prescription to a linked lab. Accepting it
    creates or links a `Patient` and creates an `EyeExam` + `Prescription` in that lab. The
    doctor only ever sees the referral itself and its status.
    """

    class Status(models.TextChoices):
        SENT = "sent", "Sent"
        RECEIVED = "received", "Received"
        IN_PROGRESS = "in_progress", "In progress"
        COMPLETED = "completed", "Completed"
        REJECTED = "rejected", "Rejected"

    OPEN = (Status.SENT, Status.RECEIVED)

    doctor = models.ForeignKey(DoctorProfile, on_delete=models.PROTECT, related_name="referrals")
    status = models.CharField(max_length=15, choices=Status.choices, default=Status.SENT, db_index=True)

    # Patient snapshot (as the doctor typed it).
    patient_name = models.CharField(max_length=200)
    patient_age = models.PositiveSmallIntegerField(null=True, blank=True)
    patient_gender = models.CharField(max_length=10, blank=True)
    patient_phone = models.CharField(max_length=30, blank=True)

    # Exam.
    exam_date = models.DateField(default=timezone.localdate)
    chief_complaint = models.CharField(max_length=300, blank=True)
    diagnosis = models.CharField(max_length=300, blank=True)
    diagnosis_details = models.TextField(blank=True)
    va_od = models.CharField(max_length=20, blank=True)
    va_os = models.CharField(max_length=20, blank=True)
    iop_od = models.DecimalField(max_digits=4, decimal_places=1, null=True, blank=True)
    iop_os = models.DecimalField(max_digits=4, decimal_places=1, null=True, blank=True)

    # Prescription (validated by `patients.rx.clean_rx`, kept as entered; null = no Rx).
    prescription_data = models.JSONField(null=True, blank=True, encoder=DjangoJSONEncoder)
    notes = models.TextField(blank=True, help_text="Doctor's note to the lab.")

    # Lab side.
    received_at = models.DateTimeField(null=True, blank=True)
    accepted_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    rejected_at = models.DateTimeField(null=True, blank=True)
    reject_reason = models.CharField(max_length=300, blank=True)
    handled_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )
    patient = models.ForeignKey(
        "patients.Patient", null=True, blank=True, on_delete=models.PROTECT, related_name="referrals"
    )
    exam = models.OneToOneField(
        "patients.EyeExam", null=True, blank=True, on_delete=models.PROTECT, related_name="referral"
    )

    class Meta:
        ordering = ["-created_at", "-id"]

    def __str__(self):
        return f"Referral {self.patient_name} → {self.lab} ({self.status})"
