from rest_framework import generics

from apps.core.permissions import IsLabOwner, IsLabOwnerOrReadOnly
from apps.core.viewsets import LabScopedNoDeleteViewSet

from .models import LabUser
from .serializers import LabSettingsSerializer, LabUserSerializer


class LabSettingsView(generics.RetrieveUpdateAPIView):
    """`GET/PATCH /api/v1/lab/` — the request's own lab (members read, owner edits)."""

    serializer_class = LabSettingsSerializer
    permission_classes = [IsLabOwnerOrReadOnly]

    def get_object(self):
        return self.request.lab


class LabUserViewSet(LabScopedNoDeleteViewSet):
    """`/api/v1/lab/users/` — owner manages the lab's users."""

    queryset = LabUser.objects.select_related("user")
    serializer_class = LabUserSerializer
    permission_classes = [IsLabOwner]
    filterset_fields = ["role", "is_active"]
    search_fields = ["user__username", "user__first_name", "user__last_name"]
    ordering_fields = ["id", "created_at"]


class LabUsageView(generics.GenericAPIView):
    """`GET /api/v1/lab/usage/` — active users / devices against the plan limits (owner)."""

    permission_classes = [IsLabOwner]

    def get(self, request):
        from rest_framework.response import Response

        from apps.accounts.models import Device

        plan = request.lab.license.plan
        return Response({
            "users": LabUser.objects.filter(lab=request.lab, is_active=True).count(),
            "max_users": plan.max_users,
            "devices": Device.objects.filter(lab=request.lab, is_active=True).count(),
            "max_devices": plan.max_devices,
        })
