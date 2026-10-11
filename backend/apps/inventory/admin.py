from django.contrib import admin

from .models import StockMovement


@admin.register(StockMovement)
class StockMovementAdmin(admin.ModelAdmin):
    """Read-only: the ledger is written only by `apps.inventory.services`."""

    list_display = ["created_at", "lab", "type", "product", "variant", "qty", "unit_cost", "qty_after", "reference_type", "reference_id"]
    list_filter = ["type", "reference_type", "lab"]
    search_fields = ["product__name", "note"]
    list_select_related = ["lab", "product", "variant"]

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
