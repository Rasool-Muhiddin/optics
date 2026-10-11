from django.contrib import admin

from .models import License, Plan


@admin.register(Plan)
class PlanAdmin(admin.ModelAdmin):
    list_display = ["name", "code", "price", "max_users", "max_devices", "doctor_linking", "report_export", "is_active"]
    list_filter = ["is_active", "doctor_linking", "report_export"]
    search_fields = ["name", "code"]
    prepopulated_fields = {"code": ["name"]}


@admin.register(License)
class LicenseAdmin(admin.ModelAdmin):
    list_display = ["lab", "plan", "starts_on", "expires_on", "is_active", "valid"]
    list_filter = ["plan", "is_active"]
    search_fields = ["lab__name"]
    autocomplete_fields = ["lab"]
    list_select_related = ["lab", "plan"]

    @admin.display(description="Valid now", boolean=True)
    def valid(self, obj):
        return obj.is_valid()
