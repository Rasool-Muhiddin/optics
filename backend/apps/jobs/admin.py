from django.contrib import admin

from .models import Job, JobCounter, JobStatusLog


class JobStatusLogInline(admin.TabularInline):
    model = JobStatusLog
    extra = 0
    can_delete = False
    fields = ["created_at", "from_status", "to_status", "note", "changed_by"]
    readonly_fields = fields

    def has_add_permission(self, request, obj=None):
        return False


@admin.register(Job)
class JobAdmin(admin.ModelAdmin):
    list_display = ["number", "lab", "patient", "status", "promised_date", "frame_source", "created_at"]
    list_filter = ["status", "frame_source", "lab"]
    search_fields = ["=number", "patient__full_name", "patient__phone"]
    list_select_related = ["lab", "patient"]
    readonly_fields = ["number", "status", "delivered_at", "created_by"]
    raw_id_fields = ["patient", "prescription", "invoice", "frame", "lens", "lens_od", "lens_os"]
    inlines = [JobStatusLogInline]

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(JobCounter)
class JobCounterAdmin(admin.ModelAdmin):
    list_display = ["lab", "last_number"]
    readonly_fields = ["lab", "last_number"]

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
