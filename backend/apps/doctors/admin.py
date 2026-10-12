from django.contrib import admin

from .models import DoctorLabLink, DoctorProfile, Referral


class DoctorLabLinkInline(admin.TabularInline):
    model = DoctorLabLink
    extra = 0
    can_delete = False
    fields = ["lab", "status", "requested_by", "requested_at", "responded_at"]
    readonly_fields = ["lab", "requested_by", "requested_at", "responded_at"]

    def has_add_permission(self, request, obj=None):
        return False


@admin.register(DoctorProfile)
class DoctorProfileAdmin(admin.ModelAdmin):
    """Tera creates doctor accounts here (create the User first, then pick it)."""

    list_display = ["full_name", "user", "specialty", "clinic_name", "phone", "link_code", "is_active"]
    list_filter = ["is_active"]
    search_fields = ["full_name", "user__username", "clinic_name", "phone", "link_code"]
    autocomplete_fields = ["user"]
    inlines = [DoctorLabLinkInline]

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(DoctorLabLink)
class DoctorLabLinkAdmin(admin.ModelAdmin):
    list_display = ["doctor", "lab", "status", "requested_by", "requested_at", "responded_at"]
    list_filter = ["status", "requested_by"]
    search_fields = ["doctor__full_name", "lab__name"]
    list_select_related = ["doctor", "lab"]
    readonly_fields = ["doctor", "lab", "requested_by", "requested_at", "responded_at"]

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(Referral)
class ReferralAdmin(admin.ModelAdmin):
    """Read-only: referrals move only through the API (accept creates patient records atomically)."""

    list_display = ["patient_name", "doctor", "lab", "status", "created_at"]
    list_filter = ["status", "lab"]
    search_fields = ["patient_name", "patient_phone", "doctor__full_name"]
    list_select_related = ["doctor", "lab"]

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
