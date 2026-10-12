import django_filters
from django.db import transaction
from rest_framework import mixins, status, viewsets
from rest_framework.response import Response

from apps.core.permissions import CanManageInventory, LabAccess
from apps.core.viewsets import LabScopedMixin

from .models import StockMovement
from .serializers import StockEntrySerializer, StockMovementSerializer
from .services import StockLine, record_movement


class StockMovementFilter(django_filters.FilterSet):
    type = django_filters.BaseInFilter(field_name="type")
    date_from = django_filters.DateFilter(field_name="created_at", lookup_expr="date__gte")
    date_to = django_filters.DateFilter(field_name="created_at", lookup_expr="date__lte")

    class Meta:
        model = StockMovement
        fields = ["product", "variant", "type", "reference_type", "reference_id"]


class StockMovementViewSet(LabScopedMixin, mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """
    `/api/v1/inventory/movements/` — the stock ledger (read: any member, costs hidden from
    staff without `can_view_costs`). `POST` (owner, or staff with `can_manage_inventory`) records a manual entry: purchase /
    adjustment / damage / return lines, all applied in one transaction.
    """

    queryset = StockMovement.objects.select_related("product", "variant", "created_by")
    serializer_class = StockMovementSerializer
    filterset_class = StockMovementFilter
    search_fields = ["product__name", "note"]
    ordering_fields = ["created_at", "id"]

    def get_permissions(self):
        return [CanManageInventory()] if self.request.method == "POST" else [LabAccess()]

    def create(self, request):
        entry = StockEntrySerializer(data=request.data, context=self.get_serializer_context())
        entry.is_valid(raise_exception=True)
        data = entry.validated_data
        with transaction.atomic():
            movements = [
                record_movement(
                    lab=request.lab,
                    line=StockLine(
                        product=line["product"], variant=line.get("variant"), qty=line["qty"],
                        unit_cost=line.get("unit_cost"),
                    ),
                    movement_type=data["type"],
                    user=request.user,
                    reference_type="manual",
                    note=data["note"],
                )
                for line in data["lines"]
            ]
        serializer = self.get_serializer(movements, many=True)
        return Response({"movements": serializer.data}, status=status.HTTP_201_CREATED)
