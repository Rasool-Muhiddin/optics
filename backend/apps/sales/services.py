"""
Sales rules. The server prices everything: the client sends items, quantities and the
discounts it wants; prices, totals, costs and the invoice number are computed here.

`checkout()` is one transaction: number → invoice → lines → `sale` stock movements → payment.
"""

from dataclasses import dataclass, field
from decimal import ROUND_HALF_UP, Decimal

from django.db import transaction
from django.utils import timezone
from rest_framework import exceptions

from apps.catalog.models import Product
from apps.core.exceptions import APIError
from apps.inventory.models import StockMovement
from apps.inventory.services import StockLine, record_movement

from .models import Invoice, InvoiceCounter, InvoiceLine, Payment

CENT = Decimal("0.01")
ZERO = Decimal("0.00")
HUNDRED = Decimal("100")


def money(value):
    return Decimal(value).quantize(CENT, rounding=ROUND_HALF_UP)


class DiscountRequiresOwner(exceptions.PermissionDenied):
    default_code = "discount_requires_owner"


@dataclass
class PricedLine:
    product: Product
    variant: object
    qty: int
    description: str
    unit_price: Decimal
    discount: Decimal
    line_total: Decimal
    available: int | None


@dataclass
class PricedCart:
    lines: list = field(default_factory=list)
    subtotal: Decimal = ZERO
    lines_discount: Decimal = ZERO
    invoice_discount_type: str = Invoice.DiscountType.AMOUNT
    invoice_discount_value: Decimal = ZERO
    invoice_discount: Decimal = ZERO
    total: Decimal = ZERO

    @property
    def discount_total(self):
        return self.lines_discount + self.invoice_discount

    @property
    def discount_percent(self):
        if self.subtotal <= 0:
            return ZERO
        return money(self.discount_total * HUNDRED / self.subtotal)


def describe(product, variant):
    if variant is None:
        return product.name
    return f"{product.name} ({variant.power_label})"


def price_cart(lines, invoice_discount_type=Invoice.DiscountType.AMOUNT, invoice_discount_value=ZERO):
    """`lines`: dicts with product, variant (or None), qty, discount and/or discount_percent."""
    cart = PricedCart(invoice_discount_type=invoice_discount_type, invoice_discount_value=money(invoice_discount_value or 0))
    for raw in lines:
        product, variant, qty = raw["product"], raw.get("variant"), raw["qty"]
        if not product.is_active or (variant is not None and not variant.is_active):
            raise APIError(f"{describe(product, variant)} is not active.", code="product_inactive")
        if product.uses_variants and variant is None:
            raise APIError("Choose the lens power.", code="variant_required")
        unit_price = money(variant.effective_sale_price if variant is not None else product.sale_price)
        gross = money(unit_price * qty)
        if raw.get("discount_percent") not in (None, ""):
            percent = Decimal(raw["discount_percent"])
            if not ZERO <= percent <= HUNDRED:
                raise APIError("Discount percent must be 0–100.", code="invalid_discount")
            discount = money(gross * percent / HUNDRED)
        else:
            discount = money(raw.get("discount") or 0)
        if discount < 0 or discount > gross:
            raise APIError("A line discount cannot exceed the line amount.", code="invalid_discount")
        if product.track_stock:
            available = (variant or product).quantity
        else:
            available = None
        cart.lines.append(
            PricedLine(product, variant, qty, describe(product, variant), unit_price, discount, gross - discount, available)
        )
        cart.subtotal += gross
        cart.lines_discount += discount

    after_lines = cart.subtotal - cart.lines_discount
    value = cart.invoice_discount_value
    if value < 0:
        raise APIError("Discount cannot be negative.", code="invalid_discount")
    if invoice_discount_type == Invoice.DiscountType.PERCENT:
        if value > HUNDRED:
            raise APIError("Discount percent must be 0–100.", code="invalid_discount")
        cart.invoice_discount = money(after_lines * value / HUNDRED)
    else:
        cart.invoice_discount = value
    if cart.invoice_discount > after_lines:
        raise APIError("The discount cannot exceed the invoice amount.", code="invalid_discount")
    cart.total = after_lines - cart.invoice_discount
    return cart


def check_discount_limit(cart, lab_user):
    """Discounts above the lab's limit (% of the subtotal) need the owner."""
    limit = lab_user.lab.max_discount_percent
    if cart.discount_total > 0 and cart.discount_percent > limit and not lab_user.is_owner:
        raise DiscountRequiresOwner(
            f"Discount {cart.discount_percent}% exceeds the staff limit of {limit}%.", code="discount_requires_owner"
        )


def next_invoice_number(lab):
    counter, _ = InvoiceCounter.objects.select_for_update().get_or_create(lab=lab)
    counter.last_number += 1
    counter.save(update_fields=["last_number"])
    return counter.last_number


def _lock_invoice(invoice):
    return Invoice.objects.select_for_update().get(pk=invoice.pk)


@transaction.atomic
def checkout(*, lab_user, user, data):
    """Creates the invoice from validated checkout `data`. Returns the saved `Invoice`."""
    lab = lab_user.lab
    cart = price_cart(data["lines"], data["invoice_discount_type"], data["invoice_discount_value"])
    check_discount_limit(cart, lab_user)

    patient = data.get("patient")
    payment_type = data["payment_type"]
    if payment_type == Invoice.PaymentType.CREDIT and patient is None:
        raise APIError("Credit sales need a patient file.", code="credit_requires_patient")
    payment = data.get("payment") or {}
    if payment_type == Invoice.PaymentType.CASH:
        pay_amount = cart.total
    else:
        pay_amount = money(payment.get("amount") or 0)
        if pay_amount < 0:
            raise APIError("Payment cannot be negative.", code="invalid_amount")
        if pay_amount > cart.total:
            raise APIError("Payment exceeds the invoice total.", code="overpayment")

    invoice = Invoice.objects.create(
        lab=lab,
        number=next_invoice_number(lab),
        patient=patient,
        customer_name=patient.full_name if patient else data.get("customer_name", ""),
        customer_phone=patient.phone if patient else data.get("customer_phone", ""),
        payment_type=payment_type,
        status=Invoice.Status.OPEN,
        subtotal=cart.subtotal,
        lines_discount=cart.lines_discount,
        invoice_discount_type=cart.invoice_discount_type,
        invoice_discount_value=cart.invoice_discount_value,
        invoice_discount=cart.invoice_discount,
        total=cart.total,
        balance=cart.total,
        cashier=user,
        notes=data.get("notes", ""),
    )

    cost_total = ZERO
    for line in cart.lines:
        if line.product.track_stock:
            movement = record_movement(
                lab=lab,
                line=StockLine(product=line.product, variant=line.variant, qty=line.qty),
                movement_type=StockMovement.Type.SALE,
                user=user,
                reference_type="invoice",
                reference_id=invoice.id,
                note=f"#{invoice.number}",
            )
            unit_cost = movement.unit_cost
        else:
            unit_cost = line.product.purchase_price  # made-to-order / services: reference cost
        cost_total += money(unit_cost * line.qty)
        InvoiceLine.objects.create(
            lab=lab, invoice=invoice, product=line.product, variant=line.variant, description=line.description,
            qty=line.qty, unit_price=line.unit_price, discount=line.discount, line_total=line.line_total,
            unit_cost=unit_cost,
        )

    invoice.cost_total = cost_total
    if pay_amount > 0:
        Payment.objects.create(
            lab=lab, invoice=invoice, amount=pay_amount, method=payment.get("method") or Payment.Method.CASH,
            received_by=user, note=payment.get("note", ""),
        )
    invoice.refresh_payment_state()
    invoice.save()
    if patient is not None:
        from apps.patients.models import Patient

        order = [s for s, _ in Patient.Status.choices]
        if order.index(patient.status) < order.index(Patient.Status.LENS_SELECTED):
            patient.status = Patient.Status.LENS_SELECTED
            patient.save(update_fields=["status", "updated_at"])
    return invoice


@transaction.atomic
def add_payment(*, invoice, amount, method, user, note=""):
    invoice = _lock_invoice(invoice)
    if invoice.status == Invoice.Status.CANCELLED:
        raise APIError("The invoice is cancelled.", code="invoice_cancelled")
    amount = money(amount)
    if amount <= 0:
        raise APIError("Amount must be positive.", code="invalid_amount")
    if amount > invoice.balance:
        raise APIError("Payment exceeds the remaining balance.", code="overpayment")
    payment = Payment.objects.create(
        lab=invoice.lab, invoice=invoice, amount=amount, method=method, received_by=user, note=note
    )
    invoice.refresh_payment_state()
    invoice.save(update_fields=["paid", "balance", "status", "updated_at"])
    return payment


@transaction.atomic
def void_payment(*, payment, user, reason):
    invoice = _lock_invoice(payment.invoice)
    if payment.is_void:
        raise APIError("Already voided.", code="record_void")
    if invoice.status == Invoice.Status.CANCELLED:
        raise APIError("The invoice is cancelled.", code="invoice_cancelled")
    payment.is_void = True
    payment.void_reason = reason
    payment.voided_at = timezone.now()
    payment.voided_by = user
    payment.save(update_fields=["is_void", "void_reason", "voided_at", "voided_by", "updated_at"])
    invoice.refresh_payment_state()
    invoice.save(update_fields=["paid", "balance", "status", "updated_at"])
    return payment


@transaction.atomic
def cancel_invoice(*, invoice, user, reason):
    """Owner: returns stock at the sold cost, voids payments (money refunded), keeps the record."""
    invoice = _lock_invoice(invoice)
    if invoice.status == Invoice.Status.CANCELLED:
        raise APIError("Already cancelled.", code="invoice_cancelled")
    for line in invoice.lines.select_related("product", "variant"):
        if line.product.track_stock:
            record_movement(
                lab=invoice.lab,
                line=StockLine(product=line.product, variant=line.variant, qty=line.qty, unit_cost=line.unit_cost),
                movement_type=StockMovement.Type.RETURN_IN,
                user=user,
                reference_type="invoice",
                reference_id=invoice.id,
                note=f"Cancel #{invoice.number}",
            )
    now = timezone.now()
    invoice.payments.filter(is_void=False).update(
        is_void=True, void_reason=f"Invoice cancelled: {reason}", voided_at=now, voided_by=user, updated_at=now
    )
    invoice.status = Invoice.Status.CANCELLED
    invoice.paid = ZERO
    invoice.balance = ZERO
    invoice.cancelled_at = now
    invoice.cancelled_by = user
    invoice.cancel_reason = reason
    invoice.save()
    return invoice


@transaction.atomic
def pay_customer(*, lab, patient, amount, method, user, note=""):
    """Spreads one payment over the patient's open credit invoices, oldest first."""
    amount = money(amount)
    if amount <= 0:
        raise APIError("Amount must be positive.", code="invalid_amount")
    invoices = list(
        Invoice.objects.select_for_update()
        .filter(lab=lab, patient=patient, balance__gt=0)
        .exclude(status=Invoice.Status.CANCELLED)
        .order_by("created_at", "id")
    )
    outstanding = sum((i.balance for i in invoices), ZERO)
    if amount > outstanding:
        raise APIError("Payment exceeds the customer's balance.", code="overpayment")
    payments, remaining = [], amount
    for invoice in invoices:
        if remaining <= 0:
            break
        part = min(remaining, invoice.balance)
        payments.append(Payment.objects.create(
            lab=lab, invoice=invoice, amount=part, method=method, received_by=user, note=note
        ))
        invoice.refresh_payment_state()
        invoice.save(update_fields=["paid", "balance", "status", "updated_at"])
        remaining -= part
    return payments
