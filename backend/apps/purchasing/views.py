import datetime

import django_filters
from django.db.models import Count, DecimalField, OuterRef, Q, Subquery, Sum, Value
from django.db.models.functions import Coalesce
from django.utils import timezone
from rest_framework import exceptions, mixins, serializers, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from apps.core.costs import request_sees_costs
from apps.core.permissions import CanManageInventory, CanManageInventoryOrReadOnly, IsLabOwner, LabAccess
from apps.core.viewsets import LabScopedMixin, LabScopedNoDeleteViewSet
from apps.sales.serializers import ReasonSerializer

from . import services
from .models import Supplier, SupplierOrder, SupplierPayment
from .serializers import SupplierOrderSerializer, SupplierPaymentSerializer, SupplierSerializer


class CanPaySuppliers(CanManageInventory):
    """Paying suppliers needs inventory management *and* cost visibility (owners have both)."""

    def has_permission(self, request, view):
        if not super().has_permission(request, view):
            return False
        if not request.lab_user.sees_costs:
            raise exceptions.PermissionDenied("Supplier money needs the cost permission.", code="cost_permission_required")
        return True


class PaySerializer(serializers.Serializer):
    amount = serializers.DecimalField(max_digits=14, decimal_places=2)
    method = serializers.ChoiceField(choices=SupplierPayment.Method.choices, default=SupplierPayment.Method.CASH)
    note = serializers.CharField(max_length=300, required=False, allow_blank=True, default="")


class ReceiveLineSerializer(serializers.Serializer):
    line = serializers.IntegerField()
    qty = serializers.IntegerField(min_value=0)


class ReceiveSerializer(serializers.Serializer):
    lines = ReceiveLineSerializer(many=True, required=False, allow_null=True, default=None)
    note = serializers.CharField(max_length=200, required=False, allow_blank=True, default="")
    supplier_ref = serializers.CharField(max_length=100, required=False, allow_blank=True)


class StatusSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=[SupplierOrder.Status.PENDING, SupplierOrder.Status.ORDERED])


def _open_balance():
    return Coalesce(Sum("orders__balance"), Value(0), output_field=DecimalField(max_digits=14, decimal_places=2))


class SupplierFilter(django_filters.FilterSet):
    has_balance = django_filters.BooleanFilter(method="filter_has_balance")

    class Meta:
        model = Supplier
        fields = ["is_active"]

    def filter_has_balance(self, queryset, name, value):
        if not request_sees_costs(self.request):
            return queryset  # not an oracle for staff without cost permission
        return queryset.filter(balance__gt=0) if value else queryset.exclude(balance__gt=0)


class SupplierViewSet(LabScopedNoDeleteViewSet):
    """
    `/api/v1/purchasing/suppliers/` — members read; owner / inventory managers edit. `balance`
    = Σ order balances (what the lab owes), only with cost permission.
    `POST {id}/pay/ {amount, method}` spreads a payment over the oldest unpaid orders.
    """

    queryset = Supplier.objects.all()
    serializer_class = SupplierSerializer
    permission_classes = [CanManageInventoryOrReadOnly]
    filterset_class = SupplierFilter
    search_fields = ["name", "phone", "notes"]
    ordering_fields = ["name", "id", "created_at"]

    def get_queryset(self):
        open_orders = (
            SupplierOrder.objects.filter(supplier=OuterRef("pk"), status__in=SupplierOrder.OPEN)
            .values("supplier").annotate(n=Count("id")).values("n")
        )
        return super().get_queryset().annotate(
            balance=_open_balance(), open_orders=Coalesce(Subquery(open_orders), Value(0))
        ).order_by("name", "id")

    @action(detail=True, methods=["post"], permission_classes=[CanPaySuppliers])
    def pay(self, request, pk=None):
        supplier = self.get_object()
        serializer = PaySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        payments = services.pay_supplier(lab=request.lab, supplier=supplier, user=request.user, **serializer.validated_data)
        return Response(
            {"payments": SupplierPaymentSerializer(payments, many=True).data}, status=status.HTTP_201_CREATED
        )


class SupplierOrderFilter(django_filters.FilterSet):
    status = django_filters.BaseInFilter(field_name="status")
    type = django_filters.BaseInFilter(field_name="type")
    payment_status = django_filters.BaseInFilter(field_name="payment_status")
    open = django_filters.BooleanFilter(method="filter_open")
    late = django_filters.BooleanFilter(method="filter_late")
    min_age = django_filters.NumberFilter(method="filter_min_age", label="Open for at least N days")
    date_from = django_filters.DateFilter(field_name="order_date", lookup_expr="gte")
    date_to = django_filters.DateFilter(field_name="order_date", lookup_expr="lte")

    class Meta:
        model = SupplierOrder
        fields = ["status", "type", "supplier", "payment_status", "job"]

    def filter_open(self, queryset, name, value):
        q = Q(status__in=SupplierOrder.OPEN)
        return queryset.filter(q) if value else queryset.exclude(q)

    def filter_late(self, queryset, name, value):
        q = Q(status__in=SupplierOrder.OPEN, expected_date__lt=timezone.localdate())
        return queryset.filter(q) if value else queryset.exclude(q)

    def filter_min_age(self, queryset, name, value):
        return queryset.filter(order_date__lte=timezone.localdate() - datetime.timedelta(days=int(value)))


AGEING_BUCKETS = ((0, 7), (8, 14), (15, 30), (31, None))


class SupplierOrderViewSet(LabScopedNoDeleteViewSet):
    """
    `/api/v1/purchasing/orders/` — supplier orders (members read, costs hidden without cost
    permission; owner / inventory managers write). Filters: `status`, `type`, `payment_status`
    (comma lists), `supplier`, `job`, `open`, `late`, `min_age`, order date range.
    Actions: `status/` (pending ⇄ ordered), `receive/`, `cancel/`, `payments/`, `GET summary/`.
    """

    queryset = SupplierOrder.objects.select_related("supplier", "job", "job__patient", "created_by").prefetch_related(
        "lines", "lines__product", "lines__variant", "payments", "payments__paid_by", "payments__supplier",
    )
    serializer_class = SupplierOrderSerializer
    permission_classes = [CanManageInventoryOrReadOnly]
    filterset_class = SupplierOrderFilter
    search_fields = ["=number", "supplier__name", "supplier_ref", "notes", "job__patient__full_name"]
    ordering_fields = ["number", "order_date", "expected_date", "created_at"]

    def _detail(self, order):
        return Response(self.get_serializer(self.get_queryset().get(pk=order.pk)).data)

    def perform_create(self, serializer):
        data = dict(serializer.validated_data)
        data.setdefault("status", SupplierOrder.Status.ORDERED)
        serializer.instance = services.create_order(lab=self.request.lab, user=self.request.user, data=data)

    def perform_update(self, serializer):
        if "lines" in serializer.validated_data and not request_sees_costs(self.request):
            # Lines are replaced wholesale: without seeing the costs they would be wiped.
            raise exceptions.PermissionDenied("Editing lines needs the cost permission.", code="cost_permission_required")
        serializer.instance = services.update_order(
            order=serializer.instance, user=self.request.user, data=dict(serializer.validated_data)
        )

    def create(self, request, *args, **kwargs):
        response = super().create(request, *args, **kwargs)
        response.data = self.get_serializer(self.get_queryset().get(pk=response.data["id"])).data
        return response

    def update(self, request, *args, **kwargs):
        super().update(request, *args, **kwargs)
        return self._detail(self.get_object())

    @action(detail=True, methods=["post"], url_path="status")
    def change_status(self, request, pk=None):
        serializer = StatusSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        order = services.change_status(
            order=self.get_object(), to_status=serializer.validated_data["status"], user=request.user
        )
        return self._detail(order)

    @action(detail=True, methods=["post"])
    def receive(self, request, pk=None):
        order = self.get_object()
        serializer = ReceiveSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        if data.get("supplier_ref"):
            SupplierOrder.objects.filter(pk=order.pk).update(supplier_ref=data["supplier_ref"])
        order = services.receive(order=order, user=request.user, lines=data["lines"], note=data["note"])
        return self._detail(order)

    @action(detail=True, methods=["post"])
    def cancel(self, request, pk=None):
        serializer = ReasonSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        order = services.cancel(order=self.get_object(), user=request.user, reason=serializer.validated_data["reason"])
        return self._detail(order)

    @action(detail=True, methods=["post"], permission_classes=[CanPaySuppliers])
    def payments(self, request, pk=None):
        order = self.get_object()
        serializer = PaySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.add_payment(order=order, user=request.user, **serializer.validated_data)
        return Response(self._detail(order).data, status=status.HTTP_201_CREATED)

    @action(detail=False, methods=["get"])
    def summary(self, request):
        """Counts per status, late and ageing buckets of open orders (+ owed total with cost permission)."""
        queryset = self.get_queryset()
        counts = dict(queryset.values_list("status").annotate(n=Count("id")).values_list("status", "n"))
        open_orders = queryset.filter(status__in=SupplierOrder.OPEN)
        today = timezone.localdate()
        buckets = []
        for low, high in AGEING_BUCKETS:
            rows = open_orders.filter(order_date__lte=today - datetime.timedelta(days=low))
            if high is not None:
                rows = rows.filter(order_date__gte=today - datetime.timedelta(days=high))
            buckets.append({"from_days": low, "to_days": high, "count": rows.count()})
        data = {
            "counts": {s: counts.get(s, 0) for s, _ in SupplierOrder.Status.choices},
            "open": open_orders.count(),
            "late": open_orders.filter(expected_date__lt=today).count(),
            "ageing": buckets,
        }
        if request_sees_costs(request):
            owed = queryset.aggregate(t=Sum("balance", filter=~Q(balance=0)))["t"]
            data["owed"] = f"{owed or 0:.2f}"
        return Response(data)


class SupplierPaymentViewSet(LabScopedMixin, mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """`/api/v1/purchasing/payments/` — supplier payments (cost permission). `POST {id}/void/` (owner)."""

    queryset = SupplierPayment.objects.select_related("supplier", "order", "paid_by")
    serializer_class = SupplierPaymentSerializer
    permission_classes = [LabAccess]
    filterset_fields = ["supplier", "order", "method", "is_void"]
    ordering_fields = ["paid_at", "id"]

    def get_queryset(self):
        queryset = super().get_queryset()
        return queryset if request_sees_costs(self.request) else queryset.none()

    @action(detail=True, methods=["post"], permission_classes=[IsLabOwner])
    def void(self, request, pk=None):
        payment = self.get_object()
        serializer = ReasonSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.void_payment(payment=payment, user=request.user, reason=serializer.validated_data["reason"])
        payment.refresh_from_db()
        return Response(self.get_serializer(payment).data)
