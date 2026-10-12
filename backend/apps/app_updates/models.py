"""Desktop version check (P10): Tera publishes installers; the app downloads and runs them."""

import hashlib
import re

from django.core.exceptions import ValidationError
from django.core.validators import FileExtensionValidator
from django.db import models
from django.utils import timezone

from apps.core.models import TimeStampedModel

VERSION_RE = re.compile(r"^\d+(\.\d+){0,3}$")


def version_key(value):
    """`"1.10.2"` → `(1, 10, 2, 0)` for comparisons (missing parts are 0)."""
    parts = [int(p) for p in (value or "0").split(".") if p.isdigit()]
    return tuple((parts + [0, 0, 0, 0])[:4])


class DesktopAppVersion(TimeStampedModel):
    """
    One published desktop release. The newest active one (by version, then build) is offered
    to every installation of that platform. Upload the installer here or point to it
    (`installer_url`, e.g. R2); its SHA-256 is computed on upload and checked by the app.
    """

    class Platform(models.TextChoices):
        WINDOWS = "windows", "Windows"

    platform = models.CharField(max_length=10, choices=Platform.choices, default=Platform.WINDOWS)
    version = models.CharField(max_length=20, help_text="Same as --build-name / APP_VERSION, e.g. 1.2.0")
    build_number = models.PositiveIntegerField(default=1)
    installer = models.FileField(
        upload_to="installers/", blank=True, validators=[FileExtensionValidator(["exe"])],
        help_text="The Inno Setup installer (.exe). Or leave empty and fill installer_url.",
    )
    installer_url = models.URLField(blank=True, help_text="External download URL (used when no file is uploaded).")
    sha256 = models.CharField(max_length=64, blank=True, help_text="Computed from the uploaded file; required for URLs.")
    size = models.PositiveBigIntegerField(default=0, editable=False)
    release_notes = models.TextField(blank=True, help_text="Shown to the user (Arabic).")
    is_mandatory = models.BooleanField(default=False, help_text="Users must install it to keep working.")
    min_supported_version = models.CharField(
        max_length=20, blank=True, help_text="Installations older than this must update (mandatory for them)."
    )
    is_active = models.BooleanField(default=True)
    published_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ["-published_at", "-id"]
        constraints = [
            models.UniqueConstraint(fields=["platform", "version", "build_number"], name="unique_desktop_version"),
        ]

    def __str__(self):
        return f"{self.get_platform_display()} {self.version}+{self.build_number}"

    def clean(self):
        super().clean()
        for field in ("version", "min_supported_version"):
            value = getattr(self, field)
            if value and not VERSION_RE.match(value):
                raise ValidationError({field: "Use digits and dots, e.g. 1.2.0"})
        if not self.installer and not self.installer_url:
            raise ValidationError("Upload an installer or give its URL.")
        if self.installer_url and not self.installer and len(self.sha256) != 64:
            raise ValidationError({"sha256": "Give the SHA-256 (64 hex chars) of the installer at that URL."})

    def save(self, *args, **kwargs):
        if self.installer and not self.installer._committed:
            digest = hashlib.sha256()
            for chunk in self.installer.chunks():
                digest.update(chunk)
            self.sha256 = digest.hexdigest()
            self.size = self.installer.size
        self.sha256 = self.sha256.lower()
        super().save(*args, **kwargs)

    @property
    def sort_key(self):
        return (*version_key(self.version), self.build_number)

    @classmethod
    def latest(cls, platform):
        rows = list(cls.objects.filter(platform=platform, is_active=True, published_at__lte=timezone.now()))
        return max(rows, key=lambda r: r.sort_key, default=None)
