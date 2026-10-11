from django.db.models import Max, Q
from rest_framework import status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.core.exceptions import APIError
from apps.core.optics import PowerError, check_axis, check_cyl, check_sph, transpose
from apps.core.permissions import LabAccess
from apps.core.viewsets import LabScopedNoDeleteViewSet

from .models import EyeExam, Patient, Prescription
from .serializers import (
    EyeExamSerializer, PatientSerializer, PrescriptionSerializer, TransposeSerializer, VoidSerializer,
)


def _advance_status(patient, to_status):
    """Moves a patient forward along the status list (never backwards)."""
    order = [s for s, _ in Patient.Status.choices]
    if order.index(to_status) > order.index(patient.status):
        patient.status = to_status
        patient.save(update_fields=["status", "updated_at"])


class VoidMixin:
    """`POST …/{id}/void/ {reason}` — owner, or the user who created the record."""

    @action(detail=True, methods=["post"])
    def void(self, request, pk=None):
        record = self.get_object()
        if record.is_void:
            raise APIError("Already voided.", code="record_void")
        if not request.lab_user.is_owner and record.created_by_id != request.user.id:
            raise APIError("Only the owner or the author can void this.", code="owner_required")
        serializer = VoidSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        self.perform_void(record, serializer.validated_data["reason"])
        return Response(self.get_serializer(record).data)

    def perform_void(self, record, reason):
        record.void(self.request.user, reason)


class PatientViewSet(LabScopedNoDeleteViewSet):
    """
    `/api/v1/patients/` — any lab member. `search` over name/phone; filters `status`, `gender`,
    `is_archived`. No delete: archive instead.
    """

    queryset = Patient.objects.annotate(
        last_exam_date=Max("exams__exam_date", filter=Q(exams__is_void=False))
    ).order_by("-created_at", "-id")
    serializer_class = PatientSerializer
    filterset_fields = ["status", "gender", "is_archived"]
    search_fields = ["full_name", "phone", "notes"]
    ordering_fields = ["full_name", "created_at", "last_exam_date", "id"]


class EyeExamViewSet(VoidMixin, LabScopedNoDeleteViewSet):
    """`/api/v1/patients/exams/?patient=` — exams with their nested `prescription`."""

    queryset = EyeExam.objects.select_related("patient", "examined_by", "prescription", "prescription__created_by")
    serializer_class = EyeExamSerializer
    filterset_fields = ["patient", "is_void", "exam_date"]
    search_fields = ["patient__full_name", "diagnosis"]
    ordering_fields = ["exam_date", "created_at", "id"]

    def perform_create(self, serializer):
        extra = {} if serializer.validated_data.get("examiner_name") else {"examined_by": self.request.user}
        serializer.save(lab=self.request.lab, created_by=self.request.user, **extra)
        _advance_status(serializer.instance.patient, Patient.Status.EXAM_DONE)

    def perform_void(self, record, reason):
        record.void(self.request.user, reason)
        rx = getattr(record, "prescription", None)
        if rx is not None and not rx.is_void:
            rx.void(self.request.user, reason)


class PrescriptionViewSet(VoidMixin, LabScopedNoDeleteViewSet):
    """`/api/v1/patients/prescriptions/?patient=` — all Rx (exam-linked and standalone)."""

    queryset = Prescription.objects.select_related("patient", "created_by")
    serializer_class = PrescriptionSerializer
    filterset_fields = ["patient", "exam", "is_void", "usage"]
    search_fields = ["patient__full_name"]
    ordering_fields = ["rx_date", "created_at", "id"]

    def perform_create(self, serializer):
        super().perform_create(serializer)
        _advance_status(serializer.instance.patient, Patient.Status.EXAM_DONE)


class TransposeView(APIView):
    """`POST /api/v1/patients/transpose/ {sph, cyl, axis}` — plus⇄minus cylinder helper."""

    permission_classes = [LabAccess]

    def post(self, request):
        serializer = TransposeSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        try:
            sph, cyl = check_sph(data["sph"]), check_cyl(data["cyl"])
            axis = check_axis(data.get("axis")) if cyl else None
        except PowerError as exc:
            raise APIError(str(exc), code=exc.code) from None
        new_sph, new_cyl, new_axis = transpose(sph, cyl, axis)
        return Response(
            {"sph": f"{new_sph:.2f}", "cyl": f"{new_cyl:.2f}", "axis": new_axis}, status=status.HTTP_200_OK
        )
