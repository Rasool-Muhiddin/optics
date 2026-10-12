import django_filters
from django.contrib.auth import authenticate
from django.db.models import Count, Q
from rest_framework import exceptions, mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import AuthToken
from apps.accounts.views import _PublicAuthView
from apps.core.exceptions import APIError
from apps.core.permissions import requires_feature
from apps.core.viewsets import LabScopedMixin
from apps.labs.models import Lab
from apps.sales.serializers import ReasonSerializer

from . import services
from .models import DoctorLabLink, Referral
from .permissions import IsDoctor
from .serializers import (
    AcceptReferralSerializer, DoctorReferralCreateSerializer, DoctorReferralSerializer, DoctorSideLinkSerializer,
    LabReferralSerializer, LabSideLinkSerializer, LinkRequestSerializer, doctor_session_payload,
)

DoctorLinkingAccess = requires_feature("doctor_linking")


def _owner_only(request):
    if not request.lab_user.is_owner:
        raise exceptions.PermissionDenied("Only the lab owner can do this.", code="owner_required")


# --- Doctor accounts --------------------------------------------------------------------


class DoctorLoginView(_PublicAuthView):
    """
    `POST /api/v1/desktop/doctor-login/ {username, password}` → `token` + doctor session.
    Doctors are not tied to a lab or a device activation (no device limits apply to them).
    """

    def post(self, request):
        username, password = request.data.get("username") or "", request.data.get("password") or ""
        if not username or not password:
            raise APIError("Username and password are required.", code="invalid_credentials")
        user = authenticate(request, username=username, password=password)
        if user is None:
            raise APIError("Invalid username or password.", code="invalid_credentials")
        profile = getattr(user, "doctor_profile", None)
        if profile is None:
            raise exceptions.PermissionDenied("This account is not a doctor account.", code="not_a_doctor")
        if not profile.is_active:
            raise exceptions.PermissionDenied("This doctor account is disabled.", code="doctor_inactive")
        _, key = AuthToken.issue(user)
        return Response({"token": key, **doctor_session_payload(profile)})


class DoctorMeView(APIView):
    """`GET /api/v1/doctor/me/` — the doctor session (used at app start)."""

    permission_classes = [IsDoctor]

    def get(self, request):
        return Response(doctor_session_payload(request.doctor))


class DoctorLinkViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """
    `/api/v1/doctor/links/` — the doctor's labs. `POST {code}` requests a link with a lab's
    link code; `POST {id}/accept|reject|revoke/`.
    """

    serializer_class = DoctorSideLinkSerializer
    permission_classes = [IsDoctor]
    filterset_fields = ["status"]

    def get_queryset(self):
        return DoctorLabLink.objects.filter(doctor=self.request.doctor).select_related("lab")

    def create(self, request):
        serializer = LinkRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        link = services.doctor_requests_link(
            doctor=request.doctor, lab_code=serializer.validated_data["code"], note=serializer.validated_data["note"]
        )
        return Response(self.get_serializer(link).data, status=status.HTTP_201_CREATED)

    def _respond(self, accept):
        link = services.respond(link=self.get_object(), side=DoctorLabLink.Side.DOCTOR, accept=accept)
        return Response(self.get_serializer(link).data)

    @action(detail=True, methods=["post"])
    def accept(self, request, pk=None):
        return self._respond(True)

    @action(detail=True, methods=["post"])
    def reject(self, request, pk=None):
        return self._respond(False)

    @action(detail=True, methods=["post"])
    def revoke(self, request, pk=None):
        return Response(self.get_serializer(services.revoke(link=self.get_object())).data)


class DoctorReferralFilter(django_filters.FilterSet):
    status = django_filters.BaseInFilter(field_name="status")

    class Meta:
        model = Referral
        fields = ["status", "lab"]


class DoctorReferralViewSet(
    mixins.ListModelMixin, mixins.RetrieveModelMixin, mixins.CreateModelMixin, viewsets.GenericViewSet
):
    """
    `/api/v1/doctor/referrals/` — the doctor's own referrals (status only on the lab side).
    `POST` sends one to an accepted lab: patient snapshot + exam + optional `prescription`.
    """

    permission_classes = [IsDoctor]
    filterset_class = DoctorReferralFilter
    search_fields = ["patient_name", "patient_phone", "lab__name"]
    ordering_fields = ["created_at", "id"]

    def get_queryset(self):
        return Referral.objects.filter(doctor=self.request.doctor).select_related("lab")

    def get_serializer_class(self):
        return DoctorReferralCreateSerializer if self.action == "create" else DoctorReferralSerializer

    def create(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = dict(serializer.validated_data)
        lab = Lab.objects.filter(pk=data.pop("lab")).first()
        if lab is None:
            raise APIError("You are not linked to this lab.", code="not_linked")
        referral = services.create_referral(doctor=request.doctor, lab=lab, data=data)
        return Response(DoctorReferralSerializer(referral).data, status=status.HTTP_201_CREATED)


# --- Lab side ---------------------------------------------------------------------------


class LabDoctorLinkViewSet(LabScopedMixin, mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """
    `/api/v1/referrals/links/` — the lab's doctors (plan `doctor_linking`). Owner: `POST {code}`
    (a doctor's link code), `POST {id}/accept|reject|revoke/`, `GET/POST code/` (the lab's own
    link code to give to doctors; POST makes a new one).
    """

    queryset = DoctorLabLink.objects.select_related("doctor")
    serializer_class = LabSideLinkSerializer
    permission_classes = [DoctorLinkingAccess]
    filterset_fields = ["status"]

    def create(self, request):
        _owner_only(request)
        serializer = LinkRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        link = services.lab_requests_link(
            lab=request.lab, doctor_code=serializer.validated_data["code"], note=serializer.validated_data["note"]
        )
        return Response(self.get_serializer(link).data, status=status.HTTP_201_CREATED)

    def _respond(self, request, accept):
        _owner_only(request)
        link = services.respond(link=self.get_object(), side=DoctorLabLink.Side.LAB, accept=accept)
        return Response(self.get_serializer(link).data)

    @action(detail=True, methods=["post"])
    def accept(self, request, pk=None):
        return self._respond(request, True)

    @action(detail=True, methods=["post"])
    def reject(self, request, pk=None):
        return self._respond(request, False)

    @action(detail=True, methods=["post"])
    def revoke(self, request, pk=None):
        _owner_only(request)
        return Response(self.get_serializer(services.revoke(link=self.get_object())).data)

    @action(detail=False, methods=["get", "post"])
    def code(self, request):
        _owner_only(request)
        lab = request.lab
        if request.method == "POST":
            from apps.core.codes import generate_link_code

            lab.doctor_link_code = generate_link_code()
            lab.save(update_fields=["doctor_link_code", "updated_at"])
        return Response({"code": lab.doctor_link_code})


class LabReferralFilter(django_filters.FilterSet):
    status = django_filters.BaseInFilter(field_name="status")
    open = django_filters.BooleanFilter(method="filter_open")

    class Meta:
        model = Referral
        fields = ["status", "doctor", "patient"]

    def filter_open(self, queryset, name, value):
        q = Q(status__in=Referral.OPEN)
        return queryset.filter(q) if value else queryset.exclude(q)


class LabReferralViewSet(LabScopedMixin, mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """
    `/api/v1/referrals/` — the lab's referral inbox (any member, plan `doctor_linking`).
    `POST {id}/receive/`, `accept/ {patient?}` (creates/links Patient + EyeExam + Prescription),
    `reject/ {reason}`, `complete/`; `GET summary/` (counts per status).
    """

    queryset = Referral.objects.select_related("doctor", "patient", "handled_by")
    serializer_class = LabReferralSerializer
    permission_classes = [DoctorLinkingAccess]
    filterset_class = LabReferralFilter
    search_fields = ["patient_name", "patient_phone", "doctor__full_name"]
    ordering_fields = ["created_at", "id"]

    def _detail(self, referral):
        return Response(self.get_serializer(self.get_queryset().get(pk=referral.pk)).data)

    @action(detail=True, methods=["post"])
    def receive(self, request, pk=None):
        return self._detail(services.mark_received(referral=self.get_object(), user=request.user))

    @action(detail=True, methods=["post"])
    def accept(self, request, pk=None):
        serializer = AcceptReferralSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        referral = services.accept(
            referral=self.get_object(), user=request.user, patient=serializer.validated_data.get("patient")
        )
        return self._detail(referral)

    @action(detail=True, methods=["post"])
    def reject(self, request, pk=None):
        serializer = ReasonSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        referral = services.reject(
            referral=self.get_object(), user=request.user, reason=serializer.validated_data["reason"]
        )
        return self._detail(referral)

    @action(detail=True, methods=["post"])
    def complete(self, request, pk=None):
        return self._detail(services.complete(referral=self.get_object(), user=request.user))

    @action(detail=False, methods=["get"])
    def summary(self, request):
        counts = dict(self.get_queryset().values_list("status").annotate(n=Count("id")).values_list("status", "n"))
        return Response({
            "counts": {s: counts.get(s, 0) for s, _ in Referral.Status.choices},
            "open": sum(counts.get(s, 0) for s in Referral.OPEN),
        })
