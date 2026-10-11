"""Patients (المراجعين), eye exams and structured prescriptions (Rx)."""

import datetime

from django.conf import settings
from django.db import models
from django.utils import timezone

from apps.core.models import LabScopedModel


class Patient(LabScopedModel):
    class Gender(models.TextChoices):
        MALE = "male", "Male"
        FEMALE = "female", "Female"

    class Status(models.TextChoices):
        NEW = "new", "New"
        EXAM_DONE = "exam_done", "Exam done"
        LENS_SELECTED = "lens_selected", "Lens selected"
        IN_JOB = "in_job", "In job"
        DELIVERED = "delivered", "Delivered"

    full_name = models.CharField(max_length=200, db_index=True)
    birth_date = models.DateField(null=True, blank=True)
    birth_date_estimated = models.BooleanField(
        default=False, help_text="Derived from an age entered at the counter (birth date unknown)."
    )
    gender = models.CharField(max_length=10, choices=Gender.choices, blank=True)
    phone = models.CharField(max_length=30, blank=True, db_index=True)
    address = models.CharField(max_length=300, blank=True)
    notes = models.TextField(blank=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.NEW, db_index=True)
    is_archived = models.BooleanField(default=False)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )

    class Meta:
        ordering = ["-created_at", "-id"]

    def __str__(self):
        return self.full_name

    @property
    def age(self):
        if not self.birth_date:
            return None
        today = timezone.localdate()
        years = today.year - self.birth_date.year
        if (today.month, today.day) < (self.birth_date.month, self.birth_date.day):
            years -= 1
        return max(years, 0)

    @staticmethod
    def birth_date_for_age(age, today=None):
        today = today or timezone.localdate()
        try:
            return today.replace(year=today.year - int(age))
        except ValueError:  # 29 February
            return (today - datetime.timedelta(days=1)).replace(year=today.year - int(age))


class VoidableModel(LabScopedModel):
    """Business records are never deleted: they are voided with a reason (CLAUDE.md §10)."""

    is_void = models.BooleanField(default=False, db_index=True)
    void_reason = models.CharField(max_length=300, blank=True)
    voided_at = models.DateTimeField(null=True, blank=True)
    voided_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )

    class Meta:
        abstract = True

    def void(self, user, reason):
        self.is_void = True
        self.void_reason = reason
        self.voided_at = timezone.now()
        self.voided_by = user
        self.save(update_fields=["is_void", "void_reason", "voided_at", "voided_by", "updated_at"])


class EyeExam(VoidableModel):
    """One examination visit. `examined_by` is a lab user; `examiner_name` covers anyone else."""

    patient = models.ForeignKey(Patient, on_delete=models.PROTECT, related_name="exams")
    exam_date = models.DateField(default=timezone.localdate, db_index=True)
    examined_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )
    examiner_name = models.CharField(max_length=150, blank=True, help_text="External doctor / optometrist.")
    chief_complaint = models.CharField(max_length=300, blank=True)
    diagnosis = models.CharField(max_length=300, blank=True)
    diagnosis_details = models.TextField(blank=True)
    va_od = models.CharField(max_length=20, blank=True, help_text="Uncorrected visual acuity, right eye.")
    va_os = models.CharField(max_length=20, blank=True, help_text="Uncorrected visual acuity, left eye.")
    iop_od = models.DecimalField(max_digits=4, decimal_places=1, null=True, blank=True, help_text="mmHg")
    iop_os = models.DecimalField(max_digits=4, decimal_places=1, null=True, blank=True, help_text="mmHg")
    notes = models.TextField(blank=True)

    class Meta:
        ordering = ["-exam_date", "-id"]

    def __str__(self):
        return f"{self.patient} — {self.exam_date}"


EYE_FIELDS = ("sph", "cyl", "axis", "add", "prism", "base", "va")


class Prescription(VoidableModel):
    """
    Structured Rx: one per exam (`exam`), or standalone (e.g. brought from another clinic).
    Cylinder is stored in minus-cyl form (plus-cyl input is transposed on save).
    """

    class Usage(models.TextChoices):
        DISTANCE = "distance", "Distance"
        NEAR = "near", "Near"
        BOTH = "both", "Distance + near"

    class Base(models.TextChoices):
        UP = "up", "Base up"
        DOWN = "down", "Base down"
        IN = "in", "Base in"
        OUT = "out", "Base out"

    patient = models.ForeignKey(Patient, on_delete=models.PROTECT, related_name="prescriptions")
    exam = models.OneToOneField(
        EyeExam, null=True, blank=True, on_delete=models.PROTECT, related_name="prescription"
    )
    rx_date = models.DateField(default=timezone.localdate)
    prescribed_by = models.CharField(max_length=150, blank=True)

    od_sph = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    od_cyl = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    od_axis = models.PositiveSmallIntegerField(null=True, blank=True)
    od_add = models.DecimalField(max_digits=4, decimal_places=2, null=True, blank=True)
    od_prism = models.DecimalField(max_digits=4, decimal_places=2, null=True, blank=True)
    od_base = models.CharField(max_length=5, choices=Base.choices, blank=True)
    od_va = models.CharField(max_length=20, blank=True, help_text="Corrected VA, right eye.")

    os_sph = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    os_cyl = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    os_axis = models.PositiveSmallIntegerField(null=True, blank=True)
    os_add = models.DecimalField(max_digits=4, decimal_places=2, null=True, blank=True)
    os_prism = models.DecimalField(max_digits=4, decimal_places=2, null=True, blank=True)
    os_base = models.CharField(max_length=5, choices=Base.choices, blank=True)
    os_va = models.CharField(max_length=20, blank=True, help_text="Corrected VA, left eye.")

    pd_distance = models.DecimalField(max_digits=4, decimal_places=1, null=True, blank=True)
    pd_near = models.DecimalField(max_digits=4, decimal_places=1, null=True, blank=True)
    pd_od = models.DecimalField(max_digits=4, decimal_places=1, null=True, blank=True, help_text="Mono PD right.")
    pd_os = models.DecimalField(max_digits=4, decimal_places=1, null=True, blank=True, help_text="Mono PD left.")

    usage = models.CharField(max_length=10, choices=Usage.choices, default=Usage.DISTANCE)
    lens_design = models.CharField(max_length=20, blank=True, help_text="single_vision / bifocal / progressive…")
    lens_index = models.CharField(max_length=5, blank=True)
    lens_coatings = models.JSONField(default=list, blank=True)
    frame_notes = models.CharField(max_length=300, blank=True)
    notes = models.TextField(blank=True)

    class Meta:
        ordering = ["-rx_date", "-id"]

    def __str__(self):
        return f"Rx {self.patient} — {self.rx_date}"
