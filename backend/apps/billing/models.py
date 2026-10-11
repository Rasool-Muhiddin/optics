"""Subscription plans (with feature flags and limits) and per-lab licenses."""

from decimal import Decimal

from django.db import models
from django.utils import timezone

from apps.core.models import TimeStampedModel

from .features import FEATURE_FLAGS


class Plan(TimeStampedModel):
    """
    A sellable plan. Feature flags are boolean fields named in `features.FEATURE_FLAGS`;
    limits are integers (0 = unlimited). Checked server-side; the UI only hides/disables.
    """

    code = models.SlugField(max_length=50, unique=True)
    name = models.CharField(max_length=100)
    description = models.TextField(blank=True)
    price = models.DecimalField(max_digits=14, decimal_places=2, default=Decimal("0"))
    is_active = models.BooleanField(default=True, help_text="Inactive plans are not sold; existing licenses keep working.")

    # Limits (0 = unlimited).
    max_users = models.PositiveIntegerField(default=3)
    max_devices = models.PositiveIntegerField(default=1)

    # Feature flags.
    doctor_linking = models.BooleanField(default=False)
    report_export = models.BooleanField(default=False)

    class Meta:
        ordering = ["price", "name"]

    def __str__(self):
        return self.name

    def has_feature(self, flag):
        if flag not in FEATURE_FLAGS:
            raise ValueError(f"Unknown feature flag: {flag}")
        return bool(getattr(self, flag))

    @property
    def features(self):
        return {flag: self.has_feature(flag) for flag in FEATURE_FLAGS}

    @property
    def limits(self):
        return {"max_users": self.max_users, "max_devices": self.max_devices}


class License(TimeStampedModel):
    """The lab's subscription. One per lab; renewing = moving `expires_on`."""

    lab = models.OneToOneField("labs.Lab", on_delete=models.CASCADE, related_name="license")
    plan = models.ForeignKey(Plan, on_delete=models.PROTECT, related_name="licenses")
    starts_on = models.DateField(default=timezone.localdate)
    expires_on = models.DateField(null=True, blank=True, help_text="Empty = never expires.")
    is_active = models.BooleanField(default=True)
    notes = models.TextField(blank=True)

    def __str__(self):
        return f"{self.lab} — {self.plan}"

    def is_valid(self, today=None):
        today = today or timezone.localdate()
        if not self.is_active or self.starts_on > today:
            return False
        return self.expires_on is None or today <= self.expires_on
