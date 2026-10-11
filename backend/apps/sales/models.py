"""Invoices (server-numbered per lab), lines with price/cost snapshots, payments, credit."""

from decimal import Decimal

from django.conf import settings
from django.db import models
from django.utils import timezone

from apps.core.models import LabScopedModel

ZERO = Decimal("0.00")


def money_field(**kwargs):
    return models.DecimalField(max_digits=14, decimal_places=2, default=ZERO, **kwargs)


class InvoiceCounter(models.Model):
    """Last invoice number of a lab; locked with `select_for_update` while numbering."""

    lab = models.OneToOneField("labs.Lab", on_delete=models.CASCADE, related_name="invoice_counter")
    last_number = models.PositiveIntegerField(default=0)

    def __str__(self):
        return f"{self.lab}: {self.last_number}"


class Invoice(LabScopedModel):
    class PaymentType(models.TextChoices):
        CASH = "cash", "Cash"
        CREDIT = "credit", "Credit (آجل)"

    class Status(models.TextChoices):
        OPEN = "open", "Open"
        PAID = "paid", "Paid"
        PARTIALLY_PAID = "partially_paid", "Partially paid"
        CANCELLED = "cancelled", "Cancelled"

    class DiscountType(models.TextChoices):
        AMOUNT = "amount", "Amount"
        PERCENT = "percent", "Percent"

    number = models.PositiveIntegerField()
    patient = models.ForeignKey(
        "patients.Patient", null=True, blank=True, on_delete=models.PROTECT, related_name="invoices"
    )
    customer_name = models.CharField(max_length=200, blank=True, help_text="Walk-in customer (no patient file).")
    customer_phone = models.CharField(max_length=30, blank=True)
    payment_type = models.CharField(max_length=10, choices=PaymentType.choices)
    status = models.CharField(max_length=20, choices=Status.choices, db_index=True)
    subtotal = money_field(help_text="Σ qty × unit price, before any discount.")
    lines_discount = money_field()
    invoice_discount_type = models.CharField(max_length=10, choices=DiscountType.choices, default=DiscountType.AMOUNT)
    invoice_discount_value = money_field(help_text="As requested (amount or percent).")
    invoice_discount = money_field(help_text="Computed amount.")
    total = money_field()
    paid = money_field()
    balance = money_field()
    cost_total = money_field(help_text="Σ qty × unit cost snapshot (for profit).")
    cashier = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")
    notes = models.TextField(blank=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)
    cancelled_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )
    cancel_reason = models.CharField(max_length=300, blank=True)

    class Meta:
        ordering = ["-number"]
        constraints = [models.UniqueConstraint(fields=["lab", "number"], name="unique_invoice_number_per_lab")]

    def __str__(self):
        return f"#{self.number} ({self.lab})"

    @property
    def discount_total(self):
        return self.lines_discount + self.invoice_discount

    @property
    def profit(self):
        return self.total - self.cost_total

    def refresh_payment_state(self):
        """Recomputes `paid` / `balance` / `status` from non-void payments (caller saves)."""
        if self.status == self.Status.CANCELLED:
            return
        self.paid = sum((p.amount for p in self.payments.filter(is_void=False)), ZERO)
        self.balance = self.total - self.paid
        if self.balance <= 0:
            self.status = self.Status.PAID
        elif self.paid > 0:
            self.status = self.Status.PARTIALLY_PAID
        else:
            self.status = self.Status.OPEN


class InvoiceLine(LabScopedModel):
    invoice = models.ForeignKey(Invoice, on_delete=models.PROTECT, related_name="lines")
    product = models.ForeignKey("catalog.Product", on_delete=models.PROTECT, related_name="+")
    variant = models.ForeignKey("catalog.LensVariant", null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    description = models.CharField(max_length=300, help_text="Snapshot: product name (+ power).")
    qty = models.PositiveIntegerField()
    unit_price = money_field(help_text="Copied from the server price at sale time.")
    discount = money_field(help_text="Discount amount on the whole line.")
    line_total = money_field()
    unit_cost = money_field(help_text="Weighted-average cost snapshot at sale time.")

    class Meta:
        ordering = ["id"]

    def __str__(self):
        return f"{self.description} × {self.qty}"


class Payment(LabScopedModel):
    class Method(models.TextChoices):
        CASH = "cash", "Cash"
        CARD = "card", "Card"
        TRANSFER = "transfer", "Transfer"
        OTHER = "other", "Other"

    invoice = models.ForeignKey(Invoice, on_delete=models.PROTECT, related_name="payments")
    amount = models.DecimalField(max_digits=14, decimal_places=2)
    method = models.CharField(max_length=10, choices=Method.choices, default=Method.CASH)
    paid_at = models.DateTimeField(default=timezone.now, db_index=True)
    received_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")
    note = models.CharField(max_length=300, blank=True)
    is_void = models.BooleanField(default=False)
    void_reason = models.CharField(max_length=300, blank=True)
    voided_at = models.DateTimeField(null=True, blank=True)
    voided_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )

    class Meta:
        ordering = ["paid_at", "id"]

    def __str__(self):
        return f"{self.amount} → #{self.invoice.number}"
