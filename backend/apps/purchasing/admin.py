from django.contrib import admin

from .models import Supplier, SupplierOrder, SupplierOrderCounter, SupplierOrderLine, SupplierPayment


@admin.register(Supplier)
class SupplierAdmin(admin.ModelAdmin):
    list_display = ["name", "lab", "phone", "is_active", "created_at"]
    list_filter = ["is_active", "lab"]
    search_fields = ["name", "phone"]
    list_select_related = ["lab"]
    readonly_fields = ["created_by"]

    def has_delete_permission(self, request, obj=None):
        return False


class _ReadOnlyInline(admin.TabularInline):
    extra = 0
    can_delete = False

    def has_add_permission(self, request, obj=None):
        return False

    def has_change_permission(self, request, obj=None):
        return False


class SupplierOrderLineInline(_ReadOnlyInline):
    model = SupplierOrderLine
    fields = ["product", "variant", "description", "eye", "qty", "unit_cost", "qty_received"]
    readonly_fields = fields


class SupplierPaymentInline(_ReadOnlyInline):
    model = SupplierPayment
    fields = ["paid_at", "amount", "method", "paid_by", "is_void", "void_reason"]
    readonly_fields = fields


@admin.register(SupplierOrder)
class SupplierOrderAdmin(admin.ModelAdmin):
    """Read-only: orders change only through the API (receiving moves stock atomically)."""

    list_display = ["number", "lab", "supplier", "type", "status", "payment_status", "order_date", "total", "balance"]
    list_filter = ["status", "payment_status", "type", "lab"]
    search_fields = ["=number", "supplier__name", "supplier_ref"]
    list_select_related = ["lab", "supplier"]
    inlines = [SupplierOrderLineInline, SupplierPaymentInline]

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(SupplierPayment)
class SupplierPaymentAdmin(admin.ModelAdmin):
    list_display = ["order", "supplier", "amount", "method", "paid_at", "is_void"]
    list_filter = ["is_void", "method", "lab"]
    list_select_related = ["order", "supplier"]

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(SupplierOrderCounter)
class SupplierOrderCounterAdmin(admin.ModelAdmin):
    list_display = ["lab", "last_number"]
    readonly_fields = ["lab", "last_number"]

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
