import django_filters
from django.db.models import Count, F, Min, Q, Sum
from rest_framework import exceptions, mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.core.pagination import StandardPagination
from apps.core.permissions import IsLabOwner, LabAccess
from apps.core.viewsets import LabScopedMixin, LabScopedReadOnlyViewSet
from apps.patients.models import Patient

from . import services
from .models import Invoice, Payment
from .serializers import (
    AddPaymentSerializer, CheckoutSerializer, InvoiceListSerializer, InvoiceSerializer, PaymentSerializer,
    ReasonSerializer,
)


class InvoiceFilter(django_filters.FilterSet):
    status = django_filters.BaseInFilter(field_name="status")
    has_balance = django_filters.BooleanFilter(method="filter_has_balance")
    date_from = django_filters.DateFilter(field_name="created_at", lookup_expr="date__gte")
    date_to = django_filters.DateFilter(field_name="created_at", lookup_expr="date__lte")

    class Meta:
        model = Invoice
        fields = ["status", "payment_type", "patient", "cashier", "number"]

    def filter_has_balance(self, queryset, name, value):
        open_ = queryset.filter(balance__gt=0).exclude(status=Invoice.Status.CANCELLED)
        return open_ if value else queryset.exclude(pk__in=open_.values("pk"))


class InvoiceViewSet(LabScopedReadOnlyViewSet):
    """
    `/api/v1/sales/invoices/` — read-only (created by checkout). Actions:
    `POST {id}/payments/` (any member), `POST {id}/cancel/` (owner: stock back, payments voided).
    """

    queryset = Invoice.objects.select_related("patient", "cashier").prefetch_related(
        "lines", "payments", "payments__received_by"
    )
    filterset_class = InvoiceFilter
    search_fields = ["=number", "customer_name", "customer_phone", "patient__full_name", "patient__phone"]
    ordering_fields = ["number", "created_at", "total", "balance"]

    def get_serializer_class(self):
        # `?with_lines=true` returns full invoices in the list (offline cache warm-up: every
        # listed invoice can then be opened and printed from the desktop cache).
        if self.action == "list" and self.request.query_params.get("with_lines") != "true":
            return InvoiceListSerializer
        return InvoiceSerializer

    @action(detail=True, methods=["post"])
    def payments(self, request, pk=None):
        invoice = self.get_object()
        serializer = AddPaymentSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.add_payment(invoice=invoice, user=request.user, **serializer.validated_data)
        invoice = self.get_queryset().get(pk=invoice.pk)
        return Response(InvoiceSerializer(invoice, context=self.get_serializer_context()).data, status=201)

    @action(detail=True, methods=["post"], permission_classes=[IsLabOwner])
    def cancel(self, request, pk=None):
        invoice = self.get_object()
        serializer = ReasonSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.cancel_invoice(invoice=invoice, user=request.user, reason=serializer.validated_data["reason"])
        invoice = self.get_queryset().get(pk=invoice.pk)
        return Response(InvoiceSerializer(invoice, context=self.get_serializer_context()).data)


class PaymentViewSet(LabScopedMixin, mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """`/api/v1/sales/payments/` — ledger of received payments; `POST {id}/void/` (owner)."""

    queryset = Payment.objects.select_related("invoice", "received_by")
    serializer_class = PaymentSerializer
    filterset_fields = ["invoice", "method", "is_void", "invoice__patient"]
    ordering_fields = ["paid_at", "id"]

    @action(detail=True, methods=["post"], permission_classes=[IsLabOwner])
    def void(self, request, pk=None):
        payment = self.get_object()
        serializer = ReasonSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.void_payment(payment=payment, user=request.user, reason=serializer.validated_data["reason"])
        payment.refresh_from_db()
        return Response(self.get_serializer(payment).data)


def _cart_payload(cart, lab_user):
    limit = lab_user.lab.max_discount_percent
    return {
        "lines": [
            {
                "product": line.product.id, "variant": line.variant.id if line.variant else None,
                "description": line.description, "qty": line.qty, "unit_price": f"{line.unit_price:.2f}",
                "discount": f"{line.discount:.2f}", "line_total": f"{line.line_total:.2f}",
                "available": line.available,
            }
            for line in cart.lines
        ],
        "subtotal": f"{cart.subtotal:.2f}",
        "lines_discount": f"{cart.lines_discount:.2f}",
        "invoice_discount": f"{cart.invoice_discount:.2f}",
        "discount_total": f"{cart.discount_total:.2f}",
        "discount_percent": f"{cart.discount_percent:.2f}",
        "total": f"{cart.total:.2f}",
        "max_discount_percent": f"{limit:.2f}",
        "requires_owner": bool(cart.discount_total and cart.discount_percent > limit),
    }


class CheckoutView(APIView):
    """`POST /api/v1/sales/checkout/` — atomic sale (invoice + stock + payment)."""

    permission_classes = [LabAccess]

    def post(self, request):
        serializer = CheckoutSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        invoice = services.checkout(lab_user=request.lab_user, user=request.user, data=serializer.validated_data)
        invoice = InvoiceViewSet.queryset.get(pk=invoice.pk)
        return Response(InvoiceSerializer(invoice, context={"request": request}).data, status=status.HTTP_201_CREATED)


class CheckoutPreviewView(APIView):
    """`POST /api/v1/sales/checkout/preview/` — the server's prices/totals for a cart; saves nothing."""

    permission_classes = [LabAccess]

    def post(self, request):
        serializer = CheckoutSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        cart = services.price_cart(data["lines"], data["invoice_discount_type"], data["invoice_discount_value"])
        return Response(_cart_payload(cart, request.lab_user))


class CreditCustomersView(APIView):
    """
    `GET /api/v1/sales/credit-customers/` — patients with an outstanding balance
    (`search` by name/phone). `POST …/{patient_id}/pay/ {amount, method}` pays oldest first.
    """

    permission_classes = [LabAccess]

    def get(self, request):
        rows = (
            Invoice.objects.filter(lab=request.lab, balance__gt=0, patient__isnull=False)
            .exclude(status=Invoice.Status.CANCELLED)
            .values("patient", name=F("patient__full_name"), phone=F("patient__phone"))
            .annotate(balance=Sum("balance"), invoices=Count("id"), oldest=Min("created_at"))
            .order_by("-balance", "patient")
        )
        search = request.query_params.get("search", "").strip()
        if search:
            rows = rows.filter(Q(patient__full_name__icontains=search) | Q(patient__phone__icontains=search))
        paginator = StandardPagination()
        page = paginator.paginate_queryset(rows, request, view=self)
        data = [
            {
                "patient": r["patient"], "name": r["name"], "phone": r["phone"], "balance": f"{r['balance']:.2f}",
                "invoices": r["invoices"], "oldest": r["oldest"].isoformat() if r["oldest"] else None,
            }
            for r in page
        ]
        return paginator.get_paginated_response(data)


class PayCustomerView(APIView):
    permission_classes = [LabAccess]

    def post(self, request, patient_id):
        patient = Patient.objects.filter(lab=request.lab, pk=patient_id).first()
        if patient is None:
            raise exceptions.NotFound("Not found.", code="not_found")
        serializer = AddPaymentSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        payments = services.pay_customer(lab=request.lab, patient=patient, user=request.user, **serializer.validated_data)
        return Response({"payments": PaymentSerializer(payments, many=True).data}, status=status.HTTP_201_CREATED)
