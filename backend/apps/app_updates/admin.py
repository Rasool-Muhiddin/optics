from django.contrib import admin

from .models import DesktopAppVersion


@admin.register(DesktopAppVersion)
class DesktopAppVersionAdmin(admin.ModelAdmin):
    """Publish a release: upload the installer (SHA-256 computed) or give URL + SHA-256."""

    list_display = ["version", "build_number", "platform", "is_mandatory", "is_active", "published_at", "size"]
    list_filter = ["platform", "is_active", "is_mandatory"]
    readonly_fields = ["size", "created_at", "updated_at"]
    fields = [
        "platform", "version", "build_number", "installer", "installer_url", "sha256", "size", "release_notes",
        "is_mandatory", "min_supported_version", "is_active", "published_at", "created_at", "updated_at",
    ]
