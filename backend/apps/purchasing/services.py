"""
Supplier-order rules. Every write that touches several rows runs in one transaction.

- Numbering: `SupplierOrderCounter` per lab (like invoices / jobs).
- Receiving creates `purchase` stock movements (weighted-average cost) for stock-tracked
  lines; made-to-order lines (rx lenses) are only marked received.
- An `rx_for_job` order's received cost replaces the reference `purchase_price` snapshot on
  the job's invoice lines for that lens (`apply_job_lens_cost`), so profit is real.
"""

from decimal import ROUND_HALF_UP, Decimal

from django.db import transaction
from django.utils import timezone

from apps.core.exceptions import APIError
from apps.inventory.models import StockMovement
from apps.inventory.services import StockLine, record_movement

from .models import SupplierOrder, SupplierOrderCounter, SupplierOrderLine, SupplierPayment

CENT = Decimal("0.01")
ZERO = Decimal("0.00")


def money(value):
    return Decimal(value).quantize(CENT, rounding=ROUND_HALF_UP)


def next_order_number(lab):
    counter, _ = SupplierOrderCounter.objects.select_for_update().get_or_create(lab=lab)
    counter.last_number += 1
    counter.save(update_fields=["last_number"])
    return counter.last_number


def _lock(order):
    return SupplierOrder.objects.select_for_update().get(pk=order.pk)


def _save_totals(order):
    order.refresh_totals()
    order.save(update_fields=["total", "paid", "balance", "payment_status", "updated_at"])


def _create_lines(order, lines):
    for line in lines:
        SupplierOrderLine.objects.create(
            lab=order.lab, order=order, product=line.get("product"), variant=line.get("variant"),
            description=line.get("description", ""), eye=line.get("eye", ""), qty=line["qty"],
            unit_cost=money(line.get("unit_cost") or 0),
        )


def _job_lens_ordered(order, user):
    """Placing an rx order moves its job from `pending` to `lens_ordered` (forward only)."""
    from apps.jobs.models import Job
    from apps.jobs.services import change_status

    job = order.job
    if job is not None and order.status == SupplierOrder.Status.ORDERED and job.status == Job.Status.PENDING:
        change_status(job=job, to_status=Job.Status.LENS_ORDERED, user=user, note=f"PO #{order.number}")


@transaction.atomic
def create_order(*, lab, user, data):
    lines = data.pop("lines")
    order = SupplierOrder.objects.create(lab=lab, number=next_order_number(lab), created_by=user, **data)
    _create_lines(order, lines)
    _save_totals(order)
    _job_lens_ordered(order, user)
    return order


@transaction.atomic
def update_order(*, order, user, data):
    order = _lock(order)
    if order.status not in SupplierOrder.EDITABLE or order.lines.filter(qty_received__gt=0).exists():
        raise APIError("Only orders that are not received or cancelled can be edited.", code="order_locked")
    if "supplier" in data and data["supplier"] != order.supplier and order.payments.exists():
        raise APIError("The supplier of an order with payments cannot change.", code="order_locked")
    lines = data.pop("lines", None)
    for field, value in data.items():
        setattr(order, field, value)
    order.save()
    if lines is not None:
        order.lines.all().delete()
        _create_lines(order, lines)
    _save_totals(order)
    if order.balance < 0:
        raise APIError("The order total cannot be less than what was already paid.", code="overpayment")
    return order


@transaction.atomic
def change_status(*, order, to_status, user):
    """Manual moves only between `pending` (not sent yet) and `ordered`."""
    order = _lock(order)
    allowed = {
        SupplierOrder.Status.PENDING: {SupplierOrder.Status.ORDERED},
        SupplierOrder.Status.ORDERED: {SupplierOrder.Status.PENDING},
    }
    if to_status not in allowed.get(order.status, set()):
        raise APIError(f"Cannot move an order from {order.status} to {to_status}.", code="invalid_transition")
    order.status = to_status
    order.save(update_fields=["status", "updated_at"])
    _job_lens_ordered(order, user)
    return order


@transaction.atomic
def receive(*, order, user, lines=None, note=""):
    """
    Receives `lines` = [{"line": SupplierOrderLine, "qty": int}] (None = everything remaining).
    Stock-tracked items get a `purchase` movement at the line's unit cost (moves the weighted
    average); the product's reference `purchase_price` becomes the last received cost.
    """
    order = _lock(order)
    if order.status in (SupplierOrder.Status.RECEIVED, SupplierOrder.Status.CANCELLED):
        raise APIError("This order is closed.", code="order_closed")
    order_lines = {line.id: line for line in order.lines.select_related("product", "variant")}
    if lines is None:
        wanted = [(line, line.qty_remaining) for line in order_lines.values() if line.qty_remaining]
    else:
        wanted = []
        for item in lines:
            line = order_lines.get(item["line"].id if hasattr(item["line"], "id") else item["line"])
            if line is None:
                raise APIError("The line does not belong to this order.", code="invalid_line")
            if item["qty"] > line.qty_remaining:
                raise APIError("Cannot receive more than was ordered.", code="over_receive")
            if item["qty"]:
                wanted.append((line, item["qty"]))
    if not wanted:
        raise APIError("Nothing to receive.", code="invalid_quantity")

    for line, qty in wanted:
        product = line.product
        if product is not None and product.track_stock:
            record_movement(
                lab=order.lab,
                line=StockLine(product=product, variant=line.variant, qty=qty, unit_cost=line.unit_cost),
                movement_type=StockMovement.Type.PURCHASE,
                user=user,
                reference_type="supplier_order",
                reference_id=order.id,
                note=(f"PO #{order.number} {note}").strip(),
            )
        if product is not None and product.purchase_price != line.unit_cost:
            type(product).objects.filter(pk=product.pk).update(purchase_price=line.unit_cost)
        line.qty_received += qty
        line.save(update_fields=["qty_received", "updated_at"])

    fully = all(line.qty_received >= line.qty for line in order.lines.all())
    order.status = SupplierOrder.Status.RECEIVED if fully else SupplierOrder.Status.PARTIALLY_RECEIVED
    order.received_at = timezone.now()
    order.save(update_fields=["status", "received_at", "updated_at"])
    _save_totals(order)
    if order.job_id:
        apply_job_lens_cost(order.job)
    return order


@transaction.atomic
def cancel(*, order, user, reason):
    """Cancels the rest of an order. What was received stays in stock and stays payable."""
    order = _lock(order)
    if order.status in (SupplierOrder.Status.RECEIVED, SupplierOrder.Status.CANCELLED):
        raise APIError("This order is closed.", code="order_closed")
    if order.paid > order.received_value:
        raise APIError(
            "More was paid than received: void the extra payments first.", code="cancel_refund_required"
        )
    order.status = SupplierOrder.Status.CANCELLED
    order.cancelled_at = timezone.now()
    order.cancelled_by = user
    order.cancel_reason = reason
    order.save(update_fields=["status", "cancelled_at", "cancelled_by", "cancel_reason", "updated_at"])
    _save_totals(order)
    if order.job_id:
        apply_job_lens_cost(order.job)
    return order


def _check_payable(order):
    if order.status == SupplierOrder.Status.PENDING:
        raise APIError("Send the order before paying it.", code="order_not_sent")


@transaction.atomic
def add_payment(*, order, amount, method, user, note=""):
    order = _lock(order)
    _check_payable(order)
    amount = money(amount)
    if amount <= 0:
        raise APIError("Amount must be positive.", code="invalid_amount")
    if amount > order.balance:
        raise APIError("Payment exceeds the order balance.", code="overpayment")
    payment = SupplierPayment.objects.create(
        lab=order.lab, supplier=order.supplier, order=order, amount=amount, method=method, paid_by=user, note=note
    )
    _save_totals(order)
    return payment


@transaction.atomic
def void_payment(*, payment, user, reason):
    order = _lock(payment.order)
    if payment.is_void:
        raise APIError("Already voided.", code="record_void")
    payment.is_void = True
    payment.void_reason = reason
    payment.voided_at = timezone.now()
    payment.voided_by = user
    payment.save(update_fields=["is_void", "void_reason", "voided_at", "voided_by", "updated_at"])
    _save_totals(order)
    return payment


@transaction.atomic
def pay_supplier(*, lab, supplier, amount, method, user, note=""):
    """Spreads one payment over the supplier's orders with a balance, oldest first."""
    amount = money(amount)
    if amount <= 0:
        raise APIError("Amount must be positive.", code="invalid_amount")
    orders = list(
        SupplierOrder.objects.select_for_update()
        .filter(lab=lab, supplier=supplier, balance__gt=0)
        .exclude(status=SupplierOrder.Status.PENDING)
        .order_by("order_date", "id")
    )
    if amount > sum((o.balance for o in orders), ZERO):
        raise APIError("Payment exceeds the supplier's balance.", code="overpayment")
    payments, remaining = [], amount
    for order in orders:
        if remaining <= 0:
            break
        part = min(remaining, order.balance)
        payments.append(SupplierPayment.objects.create(
            lab=lab, supplier=supplier, order=order, amount=part, method=method, paid_by=user, note=note
        ))
        _save_totals(order)
        remaining -= part
    return payments


def apply_job_lens_cost(job):
    """
    Puts the real supplier cost of a job's made-to-order lens on its invoice: the received
    value of the job's rx orders for that lens, spread over the invoice lines selling it.
    With nothing received (or every order cancelled before receipt) the line goes back to the
    product's reference `purchase_price`. Stock lenses keep their weighted-average cost.
    """
    from apps.sales.models import Invoice

    lens, invoice = job.lens, job.invoice
    if lens is None or invoice is None or lens.track_stock or invoice.status == Invoice.Status.CANCELLED:
        return
    with transaction.atomic():
        invoice = Invoice.objects.select_for_update().get(pk=invoice.pk)
        inv_lines = list(invoice.lines.filter(product=lens))
        if not inv_lines:
            return
        received = [
            line for line in SupplierOrderLine.objects.filter(
                order__job=job, order__type=SupplierOrder.Type.RX_FOR_JOB, product=lens, qty_received__gt=0
            )
        ]
        sold_qty = sum(line.qty for line in inv_lines)
        if received:
            unit_cost, source = money(sum((r.received_value for r in received), ZERO) / sold_qty), "supplier"
        else:
            unit_cost, source = lens.purchase_price, "reference"
        for line in inv_lines:
            line.unit_cost, line.cost_source = unit_cost, source
            line.save(update_fields=["unit_cost", "cost_source", "updated_at"])
        invoice.cost_total = sum((money(line.unit_cost * line.qty) for line in invoice.lines.all()), ZERO)
        invoice.save(update_fields=["cost_total", "updated_at"])
