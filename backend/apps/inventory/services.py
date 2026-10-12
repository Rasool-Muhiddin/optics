"""
The only code that changes stock. Every call locks the item row (`select_for_update`),
so concurrent sales/receipts can never lose an update, and must run inside
`transaction.atomic()` (callers that post several lines wrap them in one transaction).

Weighted-average cost: an incoming purchase (or a positive adjustment that states its cost,
e.g. opening stock) moves the average,
`new = (qty × avg + in_qty × in_cost) / (qty + in_qty)` (just `in_cost` when the stock was
empty or negative); every other movement is valued at the current average and leaves it.
"""

from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal

from django.db import transaction
from django.db.models import F

from apps.catalog.models import LensVariant, Product
from apps.core.exceptions import APIError

from .models import StockMovement

CENT = Decimal("0.01")


@dataclass
class StockLine:
    product: Product
    variant: LensVariant | None
    qty: int
    unit_cost: Decimal | None = None


def _money(value):
    return Decimal(value).quantize(CENT, rounding=ROUND_HALF_UP)


def signed_qty(movement_type, qty):
    """Sign `qty` by movement type; adjustments keep the sign the caller gave."""
    if movement_type == StockMovement.Type.ADJUSTMENT:
        return qty
    if movement_type in StockMovement.INCOMING:
        return abs(qty)
    return -abs(qty)


def record_movement(
    *, lab, line, movement_type, user=None, reference_type="", reference_id=None, note="", allow_negative=False
):
    """Applies one stock line and returns the `StockMovement`. Raises `APIError` on rule violations."""
    if not transaction.get_connection().in_atomic_block:
        raise RuntimeError("record_movement() must run inside transaction.atomic()")

    product = line.product
    if product.lab_id != lab.id:
        raise APIError("Item does not belong to this lab.", code="not_found")
    if not product.track_stock:
        raise APIError("This item does not track stock.", code="not_stock_tracked")
    if product.uses_variants and line.variant is None:
        raise APIError("Lens stock is tracked per power: choose a variant.", code="variant_required")
    if not product.uses_variants and line.variant is not None:
        raise APIError("This product has no power variants.", code="variant_not_allowed")
    if line.variant is not None and line.variant.product_id != product.id:
        raise APIError("Variant does not belong to the product.", code="variant_mismatch")

    qty = signed_qty(movement_type, int(line.qty))
    if qty == 0:
        raise APIError("Quantity must not be zero.", code="invalid_quantity")

    model = LensVariant if line.variant is not None else Product
    item = model.objects.select_for_update().get(pk=(line.variant or product).pk)

    new_qty = item.quantity + qty
    if new_qty < 0 and not allow_negative:
        raise APIError(
            f"Not enough stock for {item}: {item.quantity} available.", code="insufficient_stock"
        )

    average = item.average_cost
    is_purchase = movement_type == StockMovement.Type.PURCHASE
    if is_purchase and line.unit_cost is None:
        raise APIError("Purchase cost is required.", code="unit_cost_required")
    # A purchase, a customer return at its original cost, or a positive adjustment with a known
    # cost (opening stock) moves the average.
    costed_in = (StockMovement.Type.PURCHASE, StockMovement.Type.RETURN_IN, StockMovement.Type.ADJUSTMENT)
    if qty > 0 and line.unit_cost is not None and movement_type in costed_in:
        unit_cost = _money(line.unit_cost)
        if unit_cost < 0:
            raise APIError("Cost cannot be negative.", code="invalid_unit_cost")
        if item.quantity <= 0:
            average = unit_cost
        else:
            average = _money((item.quantity * item.average_cost + qty * unit_cost) / new_qty)
    else:
        unit_cost = average

    item.quantity = new_qty
    item.average_cost = average
    item.save(update_fields=["quantity", "average_cost", "updated_at"])
    if line.variant is not None:
        # The product mirrors the total of its variants (for lists / low-stock alerts).
        Product.objects.filter(pk=product.pk).update(quantity=F("quantity") + qty)

    return StockMovement.objects.create(
        lab=lab,
        product=product,
        variant=line.variant,
        type=movement_type,
        qty=qty,
        unit_cost=unit_cost,
        qty_after=new_qty,
        average_cost_after=average,
        reference_type=reference_type,
        reference_id=reference_id,
        note=note,
        created_by=user,
    )
