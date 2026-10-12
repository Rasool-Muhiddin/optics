from decimal import Decimal

from rest_framework import serializers

from apps.catalog.models import LensVariant, Product
from apps.core.costs import CostFieldsMixin
from apps.core.exceptions import APIError
from apps.core.viewsets import LabScopedPrimaryKeyRelatedField

from .models import StockMovement


class StockMovementSerializer(CostFieldsMixin, serializers.ModelSerializer):
    cost_fields = ("unit_cost", "average_cost_after", "total_cost")

    product_name = serializers.CharField(source="product.name", read_only=True)
    variant_label = serializers.SerializerMethodField()
    created_by_name = serializers.SerializerMethodField()
    total_cost = serializers.SerializerMethodField()

    class Meta:
        model = StockMovement
        fields = [
            "id", "product", "product_name", "variant", "variant_label", "type", "qty", "unit_cost",
            "total_cost", "qty_after", "average_cost_after", "reference_type", "reference_id", "note",
            "created_by", "created_by_name", "created_at",
        ]
        read_only_fields = fields

    def get_variant_label(self, obj):
        return obj.variant.power_label if obj.variant_id else ""

    def get_created_by_name(self, obj):
        user = obj.created_by
        return (user.get_full_name() or user.username) if user else ""

    def get_total_cost(self, obj):
        return str((abs(obj.qty) * obj.unit_cost).quantize(Decimal("0.01")))


MANUAL_TYPES = [
    StockMovement.Type.PURCHASE,
    StockMovement.Type.ADJUSTMENT,
    StockMovement.Type.DAMAGE,
    StockMovement.Type.RETURN_IN,
    StockMovement.Type.RETURN_OUT,
]


class StockLineSerializer(serializers.Serializer):
    product = LabScopedPrimaryKeyRelatedField(queryset=Product.objects.all(), required=False, allow_null=True)
    variant = LabScopedPrimaryKeyRelatedField(
        queryset=LensVariant.objects.select_related("product"), required=False, allow_null=True
    )
    qty = serializers.IntegerField()
    unit_cost = serializers.DecimalField(
        max_digits=14, decimal_places=2, min_value=Decimal("0"), required=False, allow_null=True
    )

    def validate(self, attrs):
        variant = attrs.get("variant")
        if variant is not None:
            if attrs.get("product") is not None and attrs["product"] != variant.product:
                raise APIError("Variant does not belong to the product.", code="variant_mismatch")
            attrs["product"] = variant.product
        if attrs.get("product") is None:
            raise serializers.ValidationError({"product": ["Product or variant is required."]})
        if attrs["qty"] == 0:
            raise serializers.ValidationError({"qty": ["Must not be zero."]})
        return attrs


class StockEntrySerializer(serializers.Serializer):
    """`POST inventory/movements/` — one manual entry of one or many lines (atomic)."""

    type = serializers.ChoiceField(choices=MANUAL_TYPES)
    note = serializers.CharField(max_length=300, required=False, allow_blank=True, default="")
    lines = StockLineSerializer(many=True, allow_empty=False, max_length=2000)
