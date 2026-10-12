"""Suppliers, supplier orders (نافذة الطلبات), receiving into stock and supplier payments."""

from decimal import Decimal

from django.conf import settings
from django.db import models
from django.utils import timezone

from apps.core.models import LabScopedModel

ZERO = Decimal("0.00")


def money_field(**kwargs):
    return models.DecimalField(max_digits=14, decimal_places=2, default=ZERO, **kwargs)


class Supplier(LabScopedModel):
    """
    A supplier of the lab. The balance (what the lab owes) is not stored: it is the sum of
    the open order balances (`SupplierOrder.balance`), see `Supplier.objects.with_balance()`.
    """

    name = models.CharField(max_length=200)
    phone = models.CharField(max_length=50, blank=True)
    address = models.CharField(max_length=300, blank=True)
    notes = models.TextField(blank=True)
    is_active = models.BooleanField(default=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )

    class Meta:
        ordering = ["name", "id"]
        constraints = [models.UniqueConstraint(fields=["lab", "name"], name="unique_supplier_name_per_lab")]

    def __str__(self):
        return self.name


class SupplierOrderCounter(models.Model):
    """Last supplier-order number of a lab (locked with `select_for_update`)."""

    lab = models.OneToOneField("labs.Lab", on_delete=models.CASCADE, related_name="supplier_order_counter")
    last_number = models.PositiveIntegerField(default=0)

    def __str__(self):
        return f"{self.lab}: {self.last_number}"


class SupplierOrder(LabScopedModel):
    class Type(models.TextChoices):
        STOCK = "stock", "Stock"
        RX_FOR_JOB = "rx_for_job", "Rx lens for a job"
        OTHER = "other", "Other"

    class Status(models.TextChoices):
        PENDING = "pending", "Pending (not sent)"
        ORDERED = "ordered", "Ordered"
        PARTIALLY_RECEIVED = "partially_received", "Partially received"
        RECEIVED = "received", "Received"
        CANCELLED = "cancelled", "Cancelled"

    class PaymentStatus(models.TextChoices):
        UNPAID = "unpaid", "Unpaid"
        PARTIAL = "partial", "Partially paid"
        PAID = "paid", "Paid"

    OPEN = (Status.PENDING, Status.ORDERED, Status.PARTIALLY_RECEIVED)
    EDITABLE = (Status.PENDING, Status.ORDERED)

    number = models.PositiveIntegerField()
    supplier = models.ForeignKey(Supplier, on_delete=models.PROTECT, related_name="orders")
    type = models.CharField(max_length=20, choices=Type.choices, default=Type.STOCK, db_index=True)
    job = models.ForeignKey(
        "jobs.Job", null=True, blank=True, on_delete=models.PROTECT, related_name="supplier_orders",
        help_text="The customer job this Rx lens is ordered for (type rx_for_job).",
    )
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING, db_index=True)
    payment_status = models.CharField(
        max_length=10, choices=PaymentStatus.choices, default=PaymentStatus.UNPAID, db_index=True
    )
    order_date = models.DateField(default=timezone.localdate, db_index=True)
    expected_date = models.DateField(null=True, blank=True, db_index=True)
    supplier_ref = models.CharField(max_length=100, blank=True, help_text="Supplier's invoice / order number.")
    notes = models.TextField(blank=True)
    total = money_field(help_text="Σ qty × unit cost (what the lab owes once received).")
    paid = money_field()
    balance = money_field(help_text="Payable − paid (payable = received value once cancelled).")
    received_at = models.DateTimeField(null=True, blank=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)
    cancelled_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )
    cancel_reason = models.CharField(max_length=300, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="+"
    )

    class Meta:
        ordering = ["-number"]
        constraints = [
            models.UniqueConstraint(fields=["lab", "number"], name="unique_supplier_order_number_per_lab")
        ]

    def __str__(self):
        return f"PO #{self.number} — {self.supplier}"

    @property
    def is_open(self):
        return self.status in self.OPEN

    def age_days(self, today=None):
        return ((today or timezone.localdate()) - self.order_date).days

    @property
    def is_late(self):
        return bool(self.expected_date and self.is_open and self.expected_date < timezone.localdate())

    @property
    def received_value(self):
        return sum((line.received_value for line in self.lines.all()), ZERO)

    @property
    def payable(self):
        """A cancelled order is only owed for what was actually received."""
        return self.received_value if self.status == self.Status.CANCELLED else self.total

    def refresh_totals(self):
        """Recomputes `total` / `paid` / `balance` / `payment_status` (caller saves)."""
        self.total = sum((line.line_total for line in self.lines.all()), ZERO)
        self.paid = sum((p.amount for p in self.payments.filter(is_void=False)), ZERO)
        self.balance = self.payable - self.paid
        if self.paid <= 0:
            self.payment_status = self.PaymentStatus.UNPAID
        elif self.balance <= 0:
            self.payment_status = self.PaymentStatus.PAID
        else:
            self.payment_status = self.PaymentStatus.PARTIAL


class SupplierOrderLine(LabScopedModel):
    """
    One ordered item. `product` may be empty for free-text lines (type `other`). Lines of
    stock-tracked products create `purchase` movements when received; others (rx lenses,
    services) are only marked received.
    """

    class Eye(models.TextChoices):
        BOTH = "", "—"
        OD = "od", "Right (OD)"
        OS = "os", "Left (OS)"

    order = models.ForeignKey(SupplierOrder, on_delete=models.CASCADE, related_name="lines")
    product = models.ForeignKey("catalog.Product", null=True, blank=True, on_delete=models.PROTECT, related_name="+")
    variant = models.ForeignKey(
        "catalog.LensVariant", null=True, blank=True, on_delete=models.PROTECT, related_name="+"
    )
    description = models.CharField(max_length=300, blank=True)
    eye = models.CharField(max_length=2, choices=Eye.choices, blank=True, default="")
    qty = models.PositiveIntegerField()
    unit_cost = money_field()
    qty_received = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["id"]

    def __str__(self):
        return f"{self.description or self.product} × {self.qty}"

    @property
    def line_total(self):
        return self.unit_cost * self.qty

    @property
    def received_value(self):
        return self.unit_cost * self.qty_received

    @property
    def qty_remaining(self):
        return max(self.qty - self.qty_received, 0)


class SupplierPayment(LabScopedModel):
    """Money paid to a supplier against one order. Never deleted: voided with a reason."""

    class Method(models.TextChoices):
        CASH = "cash", "Cash"
        CARD = "card", "Card"
        TRANSFER = "transfer", "Transfer"
        OTHER = "other", "Other"

    supplier = models.ForeignKey(Supplier, on_delete=models.PROTECT, related_name="payments")
    order = models.ForeignKey(SupplierOrder, on_delete=models.PROTECT, related_name="payments")
    amount = models.DecimalField(max_digits=14, decimal_places=2)
    method = models.CharField(max_length=10, choices=Method.choices, default=Method.CASH)
    paid_at = models.DateTimeField(default=timezone.now, db_index=True)
    paid_by = models.ForeignKey(settings.AUTH_USER_MODEL, null=True, on_delete=models.SET_NULL, related_name="+")
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
        return f"{self.amount} → PO #{self.order.number}"
