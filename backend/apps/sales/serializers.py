from decimal import Decimal

from rest_framework import serializers

from apps.catalog.models import LensVariant, Product
from apps.core.costs import CostFieldsMixin
from apps.core.viewsets import LabScopedPrimaryKeyRelatedField
from apps.patients.models import Patient

from .models import Invoice, InvoiceLine, Payment


def _name(user):
    return (user.get_full_name() or user.username) if user else ""


class InvoiceLineSerializer(CostFieldsMixin, serializers.ModelSerializer):
    cost_fields = ("unit_cost",)

    class Meta:
        model = InvoiceLine
        fields = ["id", "product", "variant", "description", "qty", "unit_price", "discount", "line_total", "unit_cost"]
        read_only_fields = fields


class PaymentSerializer(serializers.ModelSerializer):
    received_by_name = serializers.SerializerMethodField()
    invoice_number = serializers.IntegerField(source="invoice.number", read_only=True)

    class Meta:
        model = Payment
        fields = [
            "id", "invoice", "invoice_number", "amount", "method", "paid_at", "received_by", "received_by_name",
            "note", "is_void", "void_reason", "voided_at",
        ]
        read_only_fields = fields

    def get_received_by_name(self, obj):
        return _name(obj.received_by)


class InvoiceSerializer(CostFieldsMixin, serializers.ModelSerializer):
    cost_fields = ("cost_total", "profit")

    lines = InvoiceLineSerializer(many=True, read_only=True)
    payments = PaymentSerializer(many=True, read_only=True)
    cashier_name = serializers.SerializerMethodField()
    patient_name = serializers.CharField(source="patient.full_name", read_only=True, default="")
    discount_total = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True)
    profit = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True)

    class Meta:
        model = Invoice
        fields = [
            "id", "number", "patient", "patient_name", "customer_name", "customer_phone", "payment_type", "status",
            "subtotal", "lines_discount", "invoice_discount_type", "invoice_discount_value", "invoice_discount",
            "discount_total", "total", "paid", "balance", "cost_total", "profit", "cashier", "cashier_name", "notes",
            "lines", "payments", "cancelled_at", "cancel_reason", "created_at",
        ]
        read_only_fields = fields

    def get_cashier_name(self, obj):
        return _name(obj.cashier)


class InvoiceListSerializer(InvoiceSerializer):
    """Lighter rows for lists (no lines/payments)."""

    class Meta(InvoiceSerializer.Meta):
        fields = [f for f in InvoiceSerializer.Meta.fields if f not in ("lines", "payments")]
        read_only_fields = fields


class CheckoutLineSerializer(serializers.Serializer):
    product = LabScopedPrimaryKeyRelatedField(queryset=Product.objects.all(), required=False, allow_null=True)
    variant = LabScopedPrimaryKeyRelatedField(
        queryset=LensVariant.objects.select_related("product"), required=False, allow_null=True
    )
    qty = serializers.IntegerField(min_value=1, max_value=10000)
    discount = serializers.DecimalField(max_digits=14, decimal_places=2, required=False, allow_null=True)
    discount_percent = serializers.DecimalField(max_digits=5, decimal_places=2, required=False, allow_null=True)

    def validate(self, attrs):
        variant = attrs.get("variant")
        if variant is not None:
            if attrs.get("product") is not None and attrs["product"] != variant.product:
                raise serializers.ValidationError({"variant": ["Does not belong to the product."]}, code="variant_mismatch")
            attrs["product"] = variant.product
        if attrs.get("product") is None:
            raise serializers.ValidationError({"product": ["Required."]}, code="required")
        return attrs


class CheckoutPaymentSerializer(serializers.Serializer):
    amount = serializers.DecimalField(max_digits=14, decimal_places=2, required=False, default=Decimal("0"))
    method = serializers.ChoiceField(choices=Payment.Method.choices, default=Payment.Method.CASH)
    note = serializers.CharField(max_length=300, required=False, allow_blank=True, default="")


class CheckoutSerializer(serializers.Serializer):
    """
    `POST sales/checkout/` (and `sales/checkout/preview/`). Prices/totals are never accepted
    from the client — only items, quantities and requested discounts.
    """

    patient = LabScopedPrimaryKeyRelatedField(queryset=Patient.objects.all(), required=False, allow_null=True)
    customer_name = serializers.CharField(max_length=200, required=False, allow_blank=True, default="")
    customer_phone = serializers.CharField(max_length=30, required=False, allow_blank=True, default="")
    payment_type = serializers.ChoiceField(choices=Invoice.PaymentType.choices, default=Invoice.PaymentType.CASH)
    lines = CheckoutLineSerializer(many=True, allow_empty=False, max_length=200)
    invoice_discount_type = serializers.ChoiceField(
        choices=Invoice.DiscountType.choices, default=Invoice.DiscountType.AMOUNT
    )
    invoice_discount_value = serializers.DecimalField(max_digits=14, decimal_places=2, default=Decimal("0"))
    payment = CheckoutPaymentSerializer(required=False)
    notes = serializers.CharField(required=False, allow_blank=True, default="")


class AddPaymentSerializer(serializers.Serializer):
    amount = serializers.DecimalField(max_digits=14, decimal_places=2)
    method = serializers.ChoiceField(choices=Payment.Method.choices, default=Payment.Method.CASH)
    note = serializers.CharField(max_length=300, required=False, allow_blank=True, default="")


class ReasonSerializer(serializers.Serializer):
    reason = serializers.CharField(max_length=300)
