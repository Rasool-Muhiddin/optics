"""Customer glasses jobs (طلبات الزبائن): where each customer's glasses are, with a status log."""

from django.conf import settings
from django.db import models
from django.utils import timezone

from apps.core.models import LabScopedModel


class JobCounter(models.Model):
    """Last job number of a lab (locked with `select_for_update`)."""

    lab = models.OneToOneField("labs.Lab", on_delete=models.CASCADE, related_name="job_counter")
    last_number = models.PositiveIntegerField(default=0)

    def __str__(self):
        return f"{self.lab}: {self.last_number}"


class Job(LabScopedModel):
    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        LENS_ORDERED = "lens_ordered", "Lens ordered"
        IN_WORKSHOP = "in_workshop", "In workshop"
        READY = "ready", "Ready for pickup"
        DELIVERED = "delivered", "Delivered"
        CANCELLED = "cancelled", "Cancelled"

    class FrameSource(models.TextChoices):
        LAB = "lab", "Frame from the lab"
        CUSTOMER = "customer", "Customer's own frame"
        NONE = "none", "No frame (lenses only)"

    FINAL = (Status.DELIVERED, Status.CANCELLED)
    ACTIVE = (Status.PENDING, Status.LENS_ORDERED, Status.IN_WORKSHOP)

    # Allowed status moves (anything else is `invalid_transition`).
    TRANSITIONS = {
        Status.PENDING: {Status.LENS_ORDERED, Status.IN_WORKSHOP, Status.READY, Status.CANCELLED},
        Status.LENS_ORDERED: {Status.PENDING, Status.IN_WORKSHOP, Status.READY, Status.CANCELLED},
        Status.IN_WORKSHOP: {Status.LENS_ORDERED, Status.READY, Status.CANCELLED},
        Status.READY: {Status.IN_WORKSHOP, Status.DELIVERED, Status.CANCELLED},
        Status.DELIVERED: set(),
        Status.CANCELLED: set(),
    }

    number = models.PositiveIntegerField()
    patient = models.ForeignKey("patients.Patient", on_delete=models.PROTECT, related_name="jobs")
    prescription = models.ForeignKey(
        "patients.Prescription", null=True, blank=True, on_delete=models.PROTECT, related_name="jobs"
    )
    invoice = models.ForeignKey("sales.Invoice", null=True, blank=True, on_delete=models.PROTECT, related_name="jobs")
    frame_source = models.CharField(max_length=10, choices=FrameSource.choices, default=FrameSource.LAB)
    frame = models.ForeignKey("catalog.Product", null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    frame_notes = models.CharField(max_length=300, blank=True, help_text="E.g. the customer's frame description.")
    lens = models.ForeignKey("catalog.Product", null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    lens_od = models.ForeignKey(
        "catalog.LensVariant", null=True, blank=True, on_delete=models.PROTECT, related_name="+",
        help_text="Stock lens power for the right eye.",
    )
    lens_os = models.ForeignKey(
        "catalog.LensVariant", null=True, blank=True, on_delete=models.PROTECT, related_name="+",
        help_text="Stock lens power for the left eye.",
    )
    lens_notes = models.CharField(max_length=300, blank=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING, db_index=True)
    promised_date = models.DateField(null=True, blank=True, db_index=True)
    delivered_at = models.DateTimeField(null=True, blank=True)
    notes = models.TextField(blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )

    class Meta:
        ordering = ["-number"]
        constraints = [models.UniqueConstraint(fields=["lab", "number"], name="unique_job_number_per_lab")]

    def __str__(self):
        return f"Job #{self.number} — {self.patient}"

    @property
    def is_overdue(self):
        """Promised date passed while the lab is still working on it."""
        return bool(self.promised_date and self.status in self.ACTIVE and self.promised_date < timezone.localdate())


class JobStatusLog(LabScopedModel):
    job = models.ForeignKey(Job, on_delete=models.CASCADE, related_name="status_logs")
    from_status = models.CharField(max_length=20, blank=True)
    to_status = models.CharField(max_length=20)
    note = models.CharField(max_length=300, blank=True)
    changed_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")

    class Meta:
        ordering = ["created_at", "id"]

    def __str__(self):
        return f"#{self.job.number}: {self.from_status or '—'} → {self.to_status}"
