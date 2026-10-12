from django.contrib import admin

from apps.accounts.models import Device
from apps.billing.models import License

from .models import Lab, LabUser


class LicenseInline(admin.StackedInline):
    model = License
    extra = 0
    max_num = 1


class LabUserInline(admin.TabularInline):
    model = LabUser
    extra = 0
    autocomplete_fields = ["user"]
    fields = ["user", "role", "phone", "can_view_costs", "can_manage_inventory", "is_active"]


class DeviceInline(admin.TabularInline):
    model = Device
    extra = 0
    can_delete = False
    fields = ["device_id", "name", "is_active", "app_version", "last_login_at"]
    readonly_fields = ["device_id", "app_version", "last_login_at"]

    def has_add_permission(self, request, obj=None):
        return False  # devices are created by desktop activation


@admin.register(Lab)
class LabAdmin(admin.ModelAdmin):
    list_display = ["name", "phone", "currency", "plan", "license_valid", "is_active", "created_at"]
    list_filter = ["is_active", "license__plan"]
    search_fields = ["name", "phone", "activation_code"]
    readonly_fields = ["created_at", "updated_at"]
    inlines = [LicenseInline, LabUserInline, DeviceInline]
    fieldsets = [
        (None, {"fields": ["name", "phone", "address", "is_active", "notes"]}),
        ("Activation", {"fields": ["activation_code", "doctor_link_code"]}),
        ("Printing", {"fields": ["logo", "currency", "print_header", "print_footer"]}),
        ("Sales", {"fields": ["max_discount_percent"]}),
        ("Timestamps", {"fields": ["created_at", "updated_at"]}),
    ]

    @admin.display(description="Plan")
    def plan(self, obj):
        license_ = getattr(obj, "license", None)
        return license_.plan if license_ else "—"

    @admin.display(description="License valid", boolean=True)
    def license_valid(self, obj):
        license_ = getattr(obj, "license", None)
        return bool(license_ and license_.is_valid())


@admin.register(LabUser)
class LabUserAdmin(admin.ModelAdmin):
    list_display = ["user", "lab", "role", "can_view_costs", "can_manage_inventory", "is_active", "created_at"]
    list_filter = ["role", "is_active", "lab"]
    search_fields = ["user__username", "user__first_name", "user__last_name", "lab__name"]
    autocomplete_fields = ["user", "lab"]
    list_select_related = ["user", "lab"]
