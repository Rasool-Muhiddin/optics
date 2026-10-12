from decimal import Decimal

from rest_framework import serializers

from apps.catalog.models import LensVariant, Product
from apps.core.costs import CostFieldsMixin, CostOutputMixin
from apps.core.exceptions import APIError
from apps.core.viewsets import LabScopedPrimaryKeyRelatedField
from apps.jobs.models import Job

from .models import Supplier, SupplierOrder, SupplierOrderLine, SupplierPayment


def _name(user):
    return (user.get_full_name() or user.username) if user else ""


class SupplierSerializer(CostFieldsMixin, serializers.ModelSerializer):
    """`balance` (what the lab owes) is annotated by the viewset; hidden without cost permission."""

    cost_fields = ("balance",)

    balance = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True, default=Decimal("0.00"))
    open_orders = serializers.IntegerField(read_only=True, default=0)

    class Meta:
        model = Supplier
        fields = ["id", "name", "phone", "address", "notes", "is_active", "balance", "open_orders", "created_at"]
        read_only_fields = ["id", "created_at"]

    def validate_name(self, value):
        value = " ".join(value.split())
        if not value:
            raise serializers.ValidationError("Required.", code="required")
        rows = Supplier.objects.filter(lab=self.context["request"].lab, name__iexact=value)
        if self.instance is not None:
            rows = rows.exclude(pk=self.instance.pk)
        if rows.exists():
            raise APIError("A supplier with this name already exists.", code="duplicate_name")
        return value


class SupplierOrderLineSerializer(CostOutputMixin, serializers.ModelSerializer):
    """Order line. `unit_cost` may be entered by inventory managers but is only shown with cost permission."""

    output_cost_fields = ("unit_cost", "line_total")

    id = serializers.IntegerField(read_only=True)
    product = LabScopedPrimaryKeyRelatedField(queryset=Product.objects.all(), required=False, allow_null=True)
    variant = LabScopedPrimaryKeyRelatedField(
        queryset=LensVariant.objects.select_related("product"), required=False, allow_null=True
    )
    product_name = serializers.CharField(source="product.name", read_only=True, default="")
    product_kind = serializers.CharField(source="product.kind", read_only=True, default="")
    variant_label = serializers.SerializerMethodField()
    qty = serializers.IntegerField(min_value=1, max_value=100000)
    unit_cost = serializers.DecimalField(max_digits=14, decimal_places=2, min_value=Decimal("0"), default=Decimal("0"))
    line_total = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True)
    qty_remaining = serializers.IntegerField(read_only=True)

    class Meta:
        model = SupplierOrderLine
        fields = [
            "id", "product", "product_name", "product_kind", "variant", "variant_label", "description", "eye", "qty",
            "unit_cost", "line_total", "qty_received", "qty_remaining",
        ]
        read_only_fields = ["id", "qty_received"]

    def get_variant_label(self, obj):
        return obj.variant.power_label if obj.variant_id else ""

    def validate(self, attrs):
        variant = attrs.get("variant")
        if variant is not None:
            if attrs.get("product") is not None and attrs["product"] != variant.product:
                raise APIError("Variant does not belong to the product.", code="variant_mismatch")
            attrs["product"] = variant.product
        product = attrs.get("product")
        if product is not None and product.uses_variants and variant is None:
            raise APIError("Lens stock is tracked per power: choose a variant.", code="variant_required")
        if product is None and not attrs.get("description", "").strip():
            raise serializers.ValidationError({"description": ["Product or description is required."]}, code="required")
        return attrs


class SupplierPaymentSerializer(serializers.ModelSerializer):
    paid_by_name = serializers.SerializerMethodField()
    order_number = serializers.IntegerField(source="order.number", read_only=True)
    supplier_name = serializers.CharField(source="supplier.name", read_only=True)

    class Meta:
        model = SupplierPayment
        fields = [
            "id", "supplier", "supplier_name", "order", "order_number", "amount", "method", "paid_at", "paid_by",
            "paid_by_name", "note", "is_void", "void_reason", "voided_at",
        ]
        read_only_fields = fields

    def get_paid_by_name(self, obj):
        return _name(obj.paid_by)


class SupplierOrderSerializer(CostFieldsMixin, serializers.ModelSerializer):
    """
    Supplier order with nested `lines` (sent complete on create/update; replaced on update).
    Status changes go through actions (`status/`, `receive/`, `cancel/`), not through edit.
    """

    cost_fields = ("total", "paid", "balance", "payments")

    supplier = LabScopedPrimaryKeyRelatedField(queryset=Supplier.objects.all())
    supplier_name = serializers.CharField(source="supplier.name", read_only=True)
    job = LabScopedPrimaryKeyRelatedField(queryset=Job.objects.select_related("lens"), required=False, allow_null=True)
    job_number = serializers.IntegerField(source="job.number", read_only=True, default=None)
    job_patient_name = serializers.CharField(source="job.patient.full_name", read_only=True, default="")
    status = serializers.ChoiceField(
        choices=[SupplierOrder.Status.PENDING, SupplierOrder.Status.ORDERED], required=False
    )
    lines = SupplierOrderLineSerializer(many=True, allow_empty=False, max_length=2000)
    payments = SupplierPaymentSerializer(many=True, read_only=True)
    age_days = serializers.SerializerMethodField()
    is_late = serializers.BooleanField(read_only=True)
    is_open = serializers.BooleanField(read_only=True)
    created_by_name = serializers.SerializerMethodField()

    class Meta:
        model = SupplierOrder
        fields = [
            "id", "number", "supplier", "supplier_name", "type", "job", "job_number", "job_patient_name", "status",
            "payment_status", "order_date", "expected_date", "supplier_ref", "notes", "total", "paid", "balance",
            "age_days", "is_late", "is_open", "received_at", "cancelled_at", "cancel_reason", "lines", "payments",
            "created_by_name", "created_at", "updated_at",
        ]
        read_only_fields = [
            "id", "number", "payment_status", "total", "paid", "balance", "received_at", "cancelled_at",
            "cancel_reason", "created_at", "updated_at",
        ]

    def get_age_days(self, obj):
        return obj.age_days()

    def get_created_by_name(self, obj):
        return _name(obj.created_by)

    def validate(self, attrs):
        if self.instance is not None and "status" in attrs:
            raise APIError("Use the status action to change the status.", code="invalid_transition")
        order_type = attrs.get("type", getattr(self.instance, "type", SupplierOrder.Type.STOCK))
        job = attrs["job"] if "job" in attrs else getattr(self.instance, "job", None)
        lines = attrs.get("lines")

        if order_type == SupplierOrder.Type.RX_FOR_JOB:
            if job is None:
                raise serializers.ValidationError({"job": ["Required for an Rx order."]}, code="job_required")
            if "job" in attrs and job.status in Job.FINAL:
                raise APIError("A delivered or cancelled job cannot get new orders.", code="job_closed")
            for line in lines or []:
                if line.get("product") is None and job.lens is not None and not job.lens.uses_variants:
                    line["product"] = job.lens  # free-text line of an rx order = the job's lens
        elif job is not None:
            raise serializers.ValidationError({"job": ["Only Rx orders are linked to a job."]}, code="invalid_job")

        if order_type == SupplierOrder.Type.STOCK:
            for line in lines or []:
                product = line.get("product")
                if product is None or not product.track_stock:
                    raise APIError("Stock orders contain stock-tracked products only.", code="not_stock_tracked")
        return attrs
