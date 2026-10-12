from django.contrib import admin

from .models import EyeExam, Patient, Prescription


class NoDeleteAdmin(admin.ModelAdmin):
    """Business records are voided/archived, never deleted (CLAUDE.md §10)."""

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(Patient)
class PatientAdmin(NoDeleteAdmin):
    list_display = ["full_name", "phone", "gender", "status", "lab", "is_archived", "created_at"]
    list_filter = ["status", "gender", "is_archived", "lab"]
    search_fields = ["full_name", "phone"]
    list_select_related = ["lab"]


@admin.register(EyeExam)
class EyeExamAdmin(NoDeleteAdmin):
    list_display = ["patient", "exam_date", "diagnosis", "lab", "is_void"]
    list_filter = ["is_void", "lab"]
    search_fields = ["patient__full_name", "diagnosis"]
    list_select_related = ["patient", "lab"]


@admin.register(Prescription)
class PrescriptionAdmin(NoDeleteAdmin):
    list_display = ["patient", "rx_date", "od_sph", "od_cyl", "os_sph", "os_cyl", "lab", "is_void"]
    list_filter = ["is_void", "usage", "lab"]
    search_fields = ["patient__full_name"]
    list_select_related = ["patient", "lab"]
