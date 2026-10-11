"""Stock movement ledger. Current quantity / weighted-average cost live on the item rows."""

from django.conf import settings
from django.db import models

from apps.core.models import LabScopedModel


class StockMovement(LabScopedModel):
    """
    Immutable ledger row (never updated or deleted). `qty` is signed: + in, − out.

    `product` is always set (for a lens variant it is the variant's product) so a product's
    history is one filter. `unit_cost` is the purchase cost for incoming purchases and the
    weighted-average cost at that moment for everything else.
    """

    class Type(models.TextChoices):
        PURCHASE = "purchase", "Purchase"
        SALE = "sale", "Sale"
        RETURN_IN = "return_in", "Customer return"
        RETURN_OUT = "return_out", "Return to supplier"
        ADJUSTMENT = "adjustment", "Adjustment"
        DAMAGE = "damage", "Damage"

    INCOMING = (Type.PURCHASE, Type.RETURN_IN)
    OUTGOING = (Type.SALE, Type.RETURN_OUT, Type.DAMAGE)

    product = models.ForeignKey("catalog.Product", on_delete=models.PROTECT, related_name="stock_movements")
    variant = models.ForeignKey(
        "catalog.LensVariant", null=True, blank=True, on_delete=models.PROTECT, related_name="stock_movements"
    )
    type = models.CharField(max_length=20, choices=Type.choices, db_index=True)
    qty = models.IntegerField()
    unit_cost = models.DecimalField(max_digits=14, decimal_places=2)
    qty_after = models.IntegerField()
    average_cost_after = models.DecimalField(max_digits=14, decimal_places=2)
    reference_type = models.CharField(max_length=30, blank=True, help_text="invoice, supplier_order, manual…")
    reference_id = models.BigIntegerField(null=True, blank=True)
    note = models.CharField(max_length=300, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )

    class Meta:
        ordering = ["-created_at", "-id"]
        indexes = [models.Index(fields=["reference_type", "reference_id"])]

    def __str__(self):
        return f"{self.get_type_display()} {self.qty:+d} × {self.variant or self.product}"
