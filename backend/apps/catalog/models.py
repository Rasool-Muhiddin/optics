"""Categories, brands, products by kind and lens power variants (stock per variant)."""

from decimal import Decimal

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models
from django.db.models import Q

from apps.core.models import LabScopedModel

ZERO = Decimal("0.00")


class Category(LabScopedModel):
    """Product category tree (`parent` = null for top-level)."""

    name = models.CharField(max_length=100)
    parent = models.ForeignKey("self", null=True, blank=True, on_delete=models.PROTECT, related_name="children")
    is_active = models.BooleanField(default=True)

    class Meta:
        verbose_name_plural = "categories"
        ordering = ["name"]

    def __str__(self):
        return self.name

    def ancestors(self):
        node, seen = self.parent, set()
        while node is not None and node.pk not in seen:
            seen.add(node.pk)
            yield node
            node = node.parent

    def clean(self):
        super().clean()
        if self.parent_id:
            if self.parent.lab_id != self.lab_id:
                raise ValidationError({"parent": "Parent must belong to the same lab."})
            if self.pk and (self.parent_id == self.pk or any(a.pk == self.pk for a in self.parent.ancestors())):
                raise ValidationError({"parent": "A category cannot be its own ancestor."})


class Brand(LabScopedModel):
    name = models.CharField(max_length=100)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["name"]
        constraints = [models.UniqueConstraint(fields=["lab", "name"], name="unique_brand_name_per_lab")]

    def __str__(self):
        return self.name


class Product(LabScopedModel):
    """
    A sellable item. Kind-specific details live in `attributes` (see `attributes.py`).

    Stock: `stock_lens` / `contact_lens` are tracked per `LensVariant` (power); `quantity`
    here is then the sum of the variants. `rx_lens` (made to order) and `service` never
    track stock. `quantity` / `average_cost` change only through `apps.inventory.services`.
    """

    class Kind(models.TextChoices):
        FRAME = "frame", "Frame"
        STOCK_LENS = "stock_lens", "Stock lens"
        RX_LENS = "rx_lens", "Rx lens (made to order)"
        CONTACT_LENS = "contact_lens", "Contact lens"
        ACCESSORY = "accessory", "Accessory"
        SOLUTION = "solution", "Solution"
        SERVICE = "service", "Service"

    VARIANT_KINDS = (Kind.STOCK_LENS, Kind.CONTACT_LENS)
    NON_STOCK_KINDS = (Kind.RX_LENS, Kind.SERVICE)

    kind = models.CharField(max_length=20, choices=Kind.choices, db_index=True)
    name = models.CharField(max_length=200)
    brand = models.ForeignKey(Brand, null=True, blank=True, on_delete=models.PROTECT, related_name="products")
    category = models.ForeignKey(Category, null=True, blank=True, on_delete=models.PROTECT, related_name="products")
    sku = models.CharField(max_length=64, blank=True)
    barcode = models.CharField(max_length=64, blank=True)
    sale_price = models.DecimalField(max_digits=14, decimal_places=2, default=ZERO)
    purchase_price = models.DecimalField(
        max_digits=14, decimal_places=2, default=ZERO, help_text="Reference purchase price (last/expected)."
    )
    track_stock = models.BooleanField(default=True)
    quantity = models.IntegerField(default=0, editable=False)
    average_cost = models.DecimalField(max_digits=14, decimal_places=2, default=ZERO, editable=False)
    reorder_level = models.PositiveIntegerField(default=0, help_text="Low-stock threshold (0 = no alert).")
    attributes = models.JSONField(default=dict, blank=True)
    is_active = models.BooleanField(default=True)
    notes = models.TextField(blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )

    class Meta:
        ordering = ["name", "id"]
        constraints = [
            models.UniqueConstraint(fields=["lab", "sku"], condition=~Q(sku=""), name="unique_product_sku_per_lab"),
            models.UniqueConstraint(
                fields=["lab", "barcode"], condition=~Q(barcode=""), name="unique_product_barcode_per_lab"
            ),
        ]

    def __str__(self):
        return self.name

    @property
    def uses_variants(self):
        return self.kind in self.VARIANT_KINDS

    def save(self, *args, **kwargs):
        if self.kind in self.NON_STOCK_KINDS:
            self.track_stock = False
        super().save(*args, **kwargs)


class LensVariant(LabScopedModel):
    """
    One power of a stock lens / contact lens: SPH + CYL (minus-cyl, ≤ 0) + ADD (0 = none).
    Stock and weighted-average cost are tracked here, not on the product.
    """

    product = models.ForeignKey(Product, on_delete=models.PROTECT, related_name="variants")
    sph = models.DecimalField(max_digits=5, decimal_places=2)
    cyl = models.DecimalField(max_digits=5, decimal_places=2, default=ZERO)
    add = models.DecimalField(max_digits=4, decimal_places=2, default=ZERO, help_text="0 = no addition.")
    sku = models.CharField(max_length=64, blank=True)
    barcode = models.CharField(max_length=64, blank=True)
    sale_price = models.DecimalField(
        max_digits=14, decimal_places=2, null=True, blank=True, help_text="Empty = the product's sale price."
    )
    quantity = models.IntegerField(default=0, editable=False)
    average_cost = models.DecimalField(max_digits=14, decimal_places=2, default=ZERO, editable=False)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["product_id", "sph", "cyl", "add"]
        constraints = [
            models.UniqueConstraint(fields=["product", "sph", "cyl", "add"], name="unique_lens_power"),
            models.UniqueConstraint(
                fields=["lab", "barcode"], condition=~Q(barcode=""), name="unique_variant_barcode_per_lab"
            ),
        ]

    def __str__(self):
        return f"{self.product} {self.power_label}"

    @property
    def power_label(self):
        label = f"SPH {self.sph:+.2f} CYL {self.cyl:+.2f}"
        return f"{label} ADD {self.add:+.2f}" if self.add else label

    @property
    def effective_sale_price(self):
        return self.sale_price if self.sale_price is not None else self.product.sale_price
