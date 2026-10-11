"""Lab (tenant), LabUser membership and lab settings (print header, logo, currency)."""

import secrets

from django.conf import settings
from django.core.exceptions import ValidationError
from django.core.validators import FileExtensionValidator
from django.db import models

from apps.core.models import LabScopedModel, TimeStampedModel


def generate_activation_code():
    """12 uppercase hex chars, shown to the lab by Tera to activate a desktop."""
    return secrets.token_hex(6).upper()


def normalize_activation_code(value):
    return "".join(ch for ch in (value or "") if ch.isalnum()).upper()


class Lab(TimeStampedModel):
    """The tenant. Created by Tera in Django Admin (no public sign-up in v1)."""

    name = models.CharField(max_length=200)
    phone = models.CharField(max_length=50, blank=True)
    address = models.CharField(max_length=300, blank=True)
    logo = models.FileField(
        upload_to="lab_logos/",
        blank=True,
        validators=[FileExtensionValidator(["png", "jpg", "jpeg"])],
    )
    currency = models.CharField(max_length=3, default="IQD")
    print_header = models.TextField(blank=True, help_text="Extra lines printed under the lab name.")
    print_footer = models.TextField(blank=True)
    activation_code = models.CharField(
        max_length=32,
        unique=True,
        default=generate_activation_code,
        help_text="Given to the lab to activate desktop devices. Keep it secret.",
    )
    is_active = models.BooleanField(default=True)
    notes = models.TextField(blank=True, help_text="Internal (Tera only).")

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.name

    def save(self, *args, **kwargs):
        self.activation_code = normalize_activation_code(self.activation_code)
        super().save(*args, **kwargs)


class LabUser(LabScopedModel):
    """
    Membership of a user in a lab, with a role. A user belongs to at most one lab
    (doctors are separate accounts without a membership — P7).
    """

    class Role(models.TextChoices):
        OWNER = "owner", "Owner"
        STAFF = "staff", "Staff"

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="lab_membership"
    )
    role = models.CharField(max_length=20, choices=Role.choices, default=Role.STAFF)
    can_view_costs = models.BooleanField(
        default=False, help_text="Staff only: may see purchase prices and profit. Owners always can."
    )
    is_active = models.BooleanField(default=True)

    class Meta:
        verbose_name = "lab user"
        ordering = ["id"]

    def __str__(self):
        return f"{self.user} @ {self.lab} ({self.role})"

    @property
    def is_owner(self):
        return self.role == self.Role.OWNER

    @property
    def sees_costs(self):
        return self.is_owner or self.can_view_costs

    def clean(self):
        super().clean()
        if self.is_active and self.lab_id:
            from apps.billing.features import check_user_limit

            check_user_limit(self.lab, exclude_pk=self.pk, error_class=ValidationError)
