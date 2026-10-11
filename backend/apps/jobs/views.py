import django_filters
from django.db.models import Count, Q
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.response import Response

from apps.core.viewsets import LabScopedNoDeleteViewSet

from . import services
from .models import Job
from .serializers import JobSerializer, JobStatusSerializer


class JobFilter(django_filters.FilterSet):
    status = django_filters.BaseInFilter(field_name="status")
    overdue = django_filters.BooleanFilter(method="filter_overdue")
    promised_from = django_filters.DateFilter(field_name="promised_date", lookup_expr="gte")
    promised_to = django_filters.DateFilter(field_name="promised_date", lookup_expr="lte")
    delivered_from = django_filters.DateFilter(field_name="delivered_at", lookup_expr="date__gte")

    class Meta:
        model = Job
        fields = ["status", "patient", "invoice", "prescription", "frame_source"]

    def filter_overdue(self, queryset, name, value):
        overdue = Q(promised_date__lt=timezone.localdate(), status__in=Job.ACTIVE)
        return queryset.filter(overdue) if value else queryset.exclude(overdue)


class JobViewSet(LabScopedNoDeleteViewSet):
    """
    `/api/v1/jobs/` — customer glasses jobs (any lab member). Filters: `status` (comma list),
    `patient`, `overdue`, promised date range. `POST {id}/status/ {status, note}` moves a job
    along its lifecycle (logged); `GET summary/` counts per status + overdue.
    """

    queryset = Job.objects.select_related(
        "patient", "prescription", "invoice", "frame", "lens", "lens_od", "lens_os", "created_by"
    ).prefetch_related("status_logs", "status_logs__changed_by")
    serializer_class = JobSerializer
    filterset_class = JobFilter
    search_fields = ["=number", "patient__full_name", "patient__phone", "notes"]
    ordering_fields = ["number", "promised_date", "created_at", "updated_at"]

    def perform_create(self, serializer):
        job = services.create_job(lab=self.request.lab, user=self.request.user, data=serializer.validated_data)
        serializer.instance = job

    @action(detail=True, methods=["post"], url_path="status")
    def change_status(self, request, pk=None):
        job = self.get_object()
        serializer = JobStatusSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        services.change_status(
            job=job, to_status=serializer.validated_data["status"], user=request.user,
            note=serializer.validated_data["note"],
        )
        job = self.get_queryset().get(pk=job.pk)
        return Response(self.get_serializer(job).data, status=status.HTTP_200_OK)

    @action(detail=False, methods=["get"])
    def summary(self, request):
        queryset = self.get_queryset()
        counts = dict(queryset.values_list("status").annotate(n=Count("id")).values_list("status", "n"))
        overdue = queryset.filter(promised_date__lt=timezone.localdate(), status__in=Job.ACTIVE).count()
        return Response({
            "counts": {s: counts.get(s, 0) for s, _ in Job.Status.choices},
            "overdue": overdue,
        })
