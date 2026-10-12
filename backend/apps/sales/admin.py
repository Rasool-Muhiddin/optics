from django.contrib import admin

from .models import Invoice, InvoiceCounter, InvoiceLine, Payment


class ReadOnlyInline(admin.TabularInline):
    extra = 0
    can_delete = False

    def has_add_permission(self, request, obj=None):
        return False

    def has_change_permission(self, request, obj=None):
        return False


class InvoiceLineInline(ReadOnlyInline):
    model = InvoiceLine
    fields = ["description", "qty", "unit_price", "discount", "line_total", "unit_cost"]


class PaymentInline(ReadOnlyInline):
    model = Payment
    fields = ["amount", "method", "paid_at", "received_by", "is_void", "void_reason"]


@admin.register(Invoice)
class InvoiceAdmin(admin.ModelAdmin):
    """Invoices are created by checkout only and never deleted (cancel instead)."""

    list_display = ["number", "lab", "customer_name", "payment_type", "status", "total", "paid", "balance", "created_at"]
    list_filter = ["status", "payment_type", "lab"]
    search_fields = ["=number", "customer_name", "customer_phone"]
    list_select_related = ["lab"]
    inlines = [InvoiceLineInline, PaymentInline]

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(Payment)
class PaymentAdmin(admin.ModelAdmin):
    list_display = ["invoice", "lab", "amount", "method", "paid_at", "is_void"]
    list_filter = ["method", "is_void", "lab"]
    list_select_related = ["invoice", "lab"]

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(InvoiceCounter)
class InvoiceCounterAdmin(admin.ModelAdmin):
    list_display = ["lab", "last_number"]
    readonly_fields = ["lab", "last_number"]

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
