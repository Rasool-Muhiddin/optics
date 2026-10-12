from decimal import Decimal

from django.db.models import Q
from rest_framework import serializers

from apps.core.costs import CostFieldsMixin
from apps.core.exceptions import APIError
from apps.core.optics import PowerError, check_add, check_cyl, check_sph
from apps.core.viewsets import LabScopedPrimaryKeyRelatedField

from .attributes import AttributeError_, clean_attributes
from .models import Brand, Category, LensVariant, Product


def _unique_code(model, lab, field, value, exclude_pk):
    """sku / barcode must be unique within the lab across products and variants."""
    if not value:
        return
    for other in (Product, LensVariant):
        rows = other.objects.filter(lab=lab, **{field: value})
        if other is model and exclude_pk:
            rows = rows.exclude(pk=exclude_pk)
        if rows.exists():
            raise serializers.ValidationError(f"This {field} is already used.", code=f"duplicate_{field}")


class CategorySerializer(serializers.ModelSerializer):
    parent = LabScopedPrimaryKeyRelatedField(queryset=Category.objects.all(), allow_null=True, required=False)

    class Meta:
        model = Category
        fields = ["id", "name", "parent", "is_active", "created_at"]
        read_only_fields = ["id", "created_at"]

    def validate(self, attrs):
        parent = attrs.get("parent", getattr(self.instance, "parent", None))
        if parent is not None and self.instance is not None:
            if parent.pk == self.instance.pk or any(a.pk == self.instance.pk for a in parent.ancestors()):
                raise APIError("A category cannot be inside itself.", code="category_cycle")
        name = attrs.get("name", getattr(self.instance, "name", ""))
        siblings = Category.objects.filter(lab=self.context["request"].lab, parent=parent, name__iexact=name)
        if self.instance is not None:
            siblings = siblings.exclude(pk=self.instance.pk)
        if siblings.exists():
            raise APIError("A category with this name already exists here.", code="duplicate_name")
        return attrs


class BrandSerializer(serializers.ModelSerializer):
    class Meta:
        model = Brand
        fields = ["id", "name", "is_active", "created_at"]
        read_only_fields = ["id", "created_at"]

    def validate_name(self, value):
        rows = Brand.objects.filter(lab=self.context["request"].lab, name__iexact=value.strip())
        if self.instance is not None:
            rows = rows.exclude(pk=self.instance.pk)
        if rows.exists():
            raise APIError("A brand with this name already exists.", code="duplicate_name")
        return value.strip()


class ProductSerializer(CostFieldsMixin, serializers.ModelSerializer):
    cost_fields = ("purchase_price", "average_cost")

    brand = LabScopedPrimaryKeyRelatedField(queryset=Brand.objects.all(), allow_null=True, required=False)
    category = LabScopedPrimaryKeyRelatedField(queryset=Category.objects.all(), allow_null=True, required=False)
    brand_name = serializers.CharField(source="brand.name", read_only=True, default="")
    category_name = serializers.CharField(source="category.name", read_only=True, default="")
    uses_variants = serializers.BooleanField(read_only=True)
    is_low_stock = serializers.SerializerMethodField()
    sale_price = serializers.DecimalField(max_digits=14, decimal_places=2, min_value=Decimal("0"))
    purchase_price = serializers.DecimalField(
        max_digits=14, decimal_places=2, min_value=Decimal("0"), required=False
    )

    class Meta:
        model = Product
        fields = [
            "id", "kind", "name", "brand", "brand_name", "category", "category_name", "sku", "barcode",
            "sale_price", "purchase_price", "average_cost", "track_stock", "uses_variants", "quantity",
            "reorder_level", "is_low_stock", "attributes", "is_active", "notes", "created_at", "updated_at",
        ]
        read_only_fields = ["id", "quantity", "average_cost", "created_at", "updated_at"]

    def get_is_low_stock(self, obj):
        return bool(obj.track_stock and obj.reorder_level and obj.quantity <= obj.reorder_level)

    def validate_kind(self, value):
        if self.instance is not None and value != self.instance.kind:
            has_history = self.instance.stock_movements.exists() or self.instance.variants.exists()
            if has_history:
                raise APIError("The kind cannot change once the product has stock or variants.", code="kind_locked")
        return value

    def validate(self, attrs):
        lab = self.context["request"].lab
        kind = attrs.get("kind", getattr(self.instance, "kind", None))
        exclude = self.instance.pk if self.instance else None
        for field in ("sku", "barcode"):
            if field in attrs:
                attrs[field] = attrs[field].strip()
                try:
                    _unique_code(Product, lab, field, attrs[field], exclude)
                except serializers.ValidationError as exc:
                    raise serializers.ValidationError({field: exc.detail}) from None
        if "attributes" in attrs or "kind" in attrs:
            raw = attrs.get("attributes", getattr(self.instance, "attributes", {}))
            try:
                attrs["attributes"] = clean_attributes(kind, raw)
            except AttributeError_ as exc:
                raise serializers.ValidationError({"attributes": {exc.field: [str(exc)]}}) from None
        if kind in Product.NON_STOCK_KINDS:
            attrs["track_stock"] = False
        elif kind in Product.VARIANT_KINDS:
            attrs["track_stock"] = True
        if self.instance is not None and "track_stock" in attrs and not attrs["track_stock"] and self.instance.quantity:
            raise APIError("Clear the stock before turning stock tracking off.", code="stock_not_empty")
        return attrs


def _check_power(attrs, field, checker):
    if field in attrs and attrs[field] is not None:
        try:
            attrs[field] = checker(attrs[field])
        except PowerError as exc:
            raise serializers.ValidationError({field: [str(exc)]}, code=exc.code) from None


def validate_variant_powers(attrs):
    _check_power(attrs, "sph", check_sph)
    _check_power(attrs, "cyl", check_cyl)
    if attrs.get("cyl") is not None and attrs["cyl"] > 0:
        raise serializers.ValidationError({"cyl": ["Stock powers use minus cylinder (CYL ≤ 0)."]}, code="invalid_cyl")
    if attrs.get("add"):
        _check_power(attrs, "add", check_add)
    return attrs


class LensVariantSerializer(CostFieldsMixin, serializers.ModelSerializer):
    cost_fields = ("average_cost",)

    product = LabScopedPrimaryKeyRelatedField(queryset=Product.objects.filter(kind__in=Product.VARIANT_KINDS))
    product_name = serializers.CharField(source="product.name", read_only=True)
    effective_sale_price = serializers.DecimalField(max_digits=14, decimal_places=2, read_only=True)
    sale_price = serializers.DecimalField(
        max_digits=14, decimal_places=2, min_value=Decimal("0"), allow_null=True, required=False
    )

    class Meta:
        model = LensVariant
        fields = [
            "id", "product", "product_name", "sph", "cyl", "add", "sku", "barcode", "sale_price",
            "effective_sale_price", "quantity", "average_cost", "is_active", "created_at", "updated_at",
        ]
        read_only_fields = ["id", "quantity", "average_cost", "created_at", "updated_at"]
        validators = []  # uniqueness is checked in validate() with stable error codes

    def validate(self, attrs):
        if self.instance is not None:
            changing = [f for f in ("product", "sph", "cyl", "add") if f in attrs and attrs[f] != getattr(self.instance, f)]
            if changing and self.instance.stock_movements.exists():
                raise APIError("The power of a variant with stock history cannot change.", code="variant_locked")
        validate_variant_powers(attrs)
        lab = self.context["request"].lab
        for field in ("sku", "barcode"):
            if field in attrs:
                attrs[field] = attrs[field].strip()
                try:
                    _unique_code(LensVariant, lab, field, attrs[field], self.instance.pk if self.instance else None)
                except serializers.ValidationError as exc:
                    raise serializers.ValidationError({field: exc.detail}) from None
        product = attrs.get("product", getattr(self.instance, "product", None))
        key = {f: attrs.get(f, getattr(self.instance, f, Decimal("0"))) for f in ("sph", "cyl", "add")}
        key = {k: v if v is not None else Decimal("0") for k, v in key.items()}
        duplicates = LensVariant.objects.filter(product=product, **key)
        if self.instance is not None:
            duplicates = duplicates.exclude(pk=self.instance.pk)
        if duplicates.exists():
            raise APIError("This power already exists for the product.", code="duplicate_variant")
        return attrs


class GenerateVariantsSerializer(serializers.Serializer):
    """Creates every SPH × CYL combination of a range (existing powers are skipped)."""

    sph_from = serializers.DecimalField(max_digits=5, decimal_places=2)
    sph_to = serializers.DecimalField(max_digits=5, decimal_places=2)
    cyl_from = serializers.DecimalField(max_digits=5, decimal_places=2, default=Decimal("0"))
    cyl_to = serializers.DecimalField(max_digits=5, decimal_places=2, default=Decimal("0"))
    add = serializers.DecimalField(max_digits=4, decimal_places=2, default=Decimal("0"))
    step = serializers.ChoiceField(choices=["0.25", "0.50"], default="0.25")

    MAX_VARIANTS = 2000

    def validate(self, attrs):
        try:
            for name, checker in (("sph_from", check_sph), ("sph_to", check_sph), ("cyl_from", check_cyl), ("cyl_to", check_cyl)):
                attrs[name] = checker(attrs[name])
            if attrs["add"]:
                attrs["add"] = check_add(attrs["add"])
        except PowerError as exc:
            raise APIError(str(exc), code=exc.code) from None
        if attrs["cyl_from"] > 0 or attrs["cyl_to"] > 0:
            raise APIError("Stock powers use minus cylinder (CYL ≤ 0).", code="invalid_cyl")
        step = Decimal(attrs["step"])
        sph_lo, sph_hi = sorted([attrs["sph_from"], attrs["sph_to"]])
        cyl_lo, cyl_hi = sorted([attrs["cyl_from"], attrs["cyl_to"]])
        count = (int((sph_hi - sph_lo) / step) + 1) * (int((cyl_hi - cyl_lo) / step) + 1)
        if count > self.MAX_VARIANTS:
            raise APIError(f"At most {self.MAX_VARIANTS} powers at once.", code="too_many_variants")
        attrs["powers"] = [
            (sph_lo + i * step, cyl_lo + j * step)
            for i in range(int((sph_hi - sph_lo) / step) + 1)
            for j in range(int((cyl_hi - cyl_lo) / step) + 1)
        ]
        return attrs


def lookup_code(lab, code):
    """Product or variant by exact barcode/sku (for barcode scanners)."""
    code = (code or "").strip()
    if not code:
        return None, None
    variant = (
        LensVariant.objects.select_related("product")
        .filter(lab=lab, is_active=True)
        .filter(Q(barcode=code) | Q(sku=code))
        .first()
    )
    if variant:
        return variant.product, variant
    product = Product.objects.filter(lab=lab, is_active=True).filter(Q(barcode=code) | Q(sku=code)).first()
    return product, None
