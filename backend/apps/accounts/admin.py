from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as DjangoUserAdmin

from .models import AuthToken, Device, User


@admin.register(User)
class UserAdmin(DjangoUserAdmin):
    list_display = ["username", "first_name", "last_name", "lab", "is_active", "is_staff"]
    list_select_related = ["lab_membership__lab"]

    @admin.display(description="Lab")
    def lab(self, obj):
        membership = getattr(obj, "lab_membership", None)
        return membership.lab if membership else "—"


@admin.register(Device)
class DeviceAdmin(admin.ModelAdmin):
    list_display = ["name", "device_id", "lab", "is_active", "app_version", "last_login_at", "created_at"]
    list_filter = ["is_active", "lab"]
    search_fields = ["name", "device_id", "lab__name"]
    readonly_fields = ["lab", "device_id", "app_version", "last_login_at", "created_at", "updated_at"]
    list_select_related = ["lab"]

    def has_add_permission(self, request):
        return False  # devices are created by desktop activation


@admin.register(AuthToken)
class AuthTokenAdmin(admin.ModelAdmin):
    """Read-only list of sessions; deleting a row logs that device out."""

    list_display = ["user", "device", "created_at"]
    search_fields = ["user__username"]
    list_select_related = ["user", "device"]
    readonly_fields = ["user", "device", "created_at"]

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False
