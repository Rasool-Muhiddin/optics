from django.contrib.auth import authenticate
from django.core.exceptions import ObjectDoesNotExist
from django.db import transaction
from django.utils import timezone
from rest_framework import exceptions, mixins, status, viewsets
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.billing.features import check_device_limit
from apps.core.exceptions import APIError
from apps.core.permissions import IsLabOwner, LabAccess
from apps.core.throttling import ClientIPScopedRateThrottle
from apps.core.tenancy import check_lab_access, get_membership
from apps.core.viewsets import LabScopedMixin
from apps.labs.models import Lab, normalize_activation_code

from .models import AuthToken, Device, hash_secret
from .serializers import ActivateSerializer, DeviceSerializer, LoginSerializer, session_payload


class _PublicAuthView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_classes = [ClientIPScopedRateThrottle]
    throttle_scope = "desktop_auth"


class ActivateView(_PublicAuthView):
    """
    `POST /api/v1/desktop/activate/` `{activation_code, device_id, device_name?, app_version?}`
    → `{device_key, device, lab}`. Re-activating the same `device_id` rotates its key and
    does not take a new device slot. The app stores `device_key` and sends it on login.
    """

    def post(self, request):
        serializer = ActivateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        with transaction.atomic():
            # Lock the lab row so concurrent activations cannot exceed `max_devices`.
            lab = (
                Lab.objects.select_for_update()
                .filter(activation_code=normalize_activation_code(data["activation_code"]))
                .first()
            )
            if lab is None:
                raise APIError("Invalid activation code.", code="invalid_activation_code")
            _check_lab_usable(lab)

            device = Device.objects.filter(lab=lab, device_id=data["device_id"]).first()
            if device is None or not device.is_active:
                check_device_limit(lab, exclude_pk=device.pk if device else None, error_class=_Forbidden)
            if device is None:
                device = Device(lab=lab, device_id=data["device_id"])
            device.name = data["device_name"] or device.name
            device.app_version = data["app_version"]
            device.is_active = True
            key = device.rotate_key()
            device.save()
            # A rotated key invalidates sessions opened with the old one.
            device.auth_tokens.all().delete()

        return Response(
            {
                "device_key": key,
                "device": {"id": device.id, "name": device.name},
                "lab": {"id": lab.id, "name": lab.name},
            },
            status=status.HTTP_201_CREATED,
        )


class LoginView(_PublicAuthView):
    """
    `POST /api/v1/desktop/login/` `{username, password, device_key}` → session + `token`.
    The user must be an active member of the lab the device was activated for.
    """

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        device = Device.objects.select_related("lab").filter(key_digest=hash_secret(data["device_key"])).first()
        if device is None or not device.is_active:
            raise _Forbidden("This device is not activated.", code="device_not_activated")

        user = authenticate(request, username=data["username"], password=data["password"])
        if user is None:
            raise APIError("Invalid username or password.", code="invalid_credentials")

        membership = get_membership(user)
        check_lab_access(membership)
        if membership.lab_id != device.lab_id:
            raise _Forbidden("This user does not belong to this device's lab.", code="device_lab_mismatch")

        token, key = AuthToken.issue(user, device)
        device.last_login_at = timezone.now()
        if data["app_version"]:
            device.app_version = data["app_version"]
        device.save(update_fields=["last_login_at", "app_version", "updated_at"])
        user.last_login = device.last_login_at
        user.save(update_fields=["last_login"])

        return Response({"token": key, **session_payload(membership, device)})


class MeView(APIView):
    """`GET /api/v1/auth/me/` — current session (used at app start to validate a stored token)."""

    permission_classes = [LabAccess]

    def get(self, request):
        token = request.auth if isinstance(request.auth, AuthToken) else None
        return Response(session_payload(request.lab_user, token.device if token else None))


class LogoutView(APIView):
    """`POST /api/v1/auth/logout/` — revokes only the token used for this request."""

    def post(self, request):
        if isinstance(request.auth, AuthToken):
            request.auth.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class DeviceViewSet(
    LabScopedMixin,
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    mixins.UpdateModelMixin,
    viewsets.GenericViewSet,
):
    """
    `/api/v1/lab/devices/` — owner renames or (de)activates devices. Devices are created
    only by activation; deactivating one revokes its sessions at once.
    """

    queryset = Device.objects.all()
    serializer_class = DeviceSerializer
    permission_classes = [IsLabOwner]
    filterset_fields = ["is_active"]

    def perform_update(self, serializer):
        device = serializer.instance
        if serializer.validated_data.get("is_active") and not device.is_active:
            check_device_limit(self.request.lab, exclude_pk=device.pk, error_class=APIError)
        serializer.save()
        if not serializer.instance.is_active:
            serializer.instance.auth_tokens.all().delete()  # revoked: sessions end now


class _Forbidden(exceptions.PermissionDenied):
    pass


def _check_lab_usable(lab):
    """Activation-time version of the request gate (there is no user yet)."""
    if not lab.is_active:
        raise _Forbidden("Lab is disabled.", code="lab_inactive")
    try:
        license_ = lab.license
    except ObjectDoesNotExist:
        raise _Forbidden("Lab has no license.", code="no_license") from None
    if not license_.is_valid():
        raise _Forbidden("Lab license has expired.", code="license_expired")
