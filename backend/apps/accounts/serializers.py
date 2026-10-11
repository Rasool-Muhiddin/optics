from rest_framework import serializers

from apps.labs.serializers import LabSettingsSerializer

from .models import Device, User


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["id", "username", "first_name", "last_name", "email"]
        read_only_fields = fields


class ActivateSerializer(serializers.Serializer):
    activation_code = serializers.CharField(max_length=64)
    device_id = serializers.CharField(max_length=64)
    device_name = serializers.CharField(max_length=100, required=False, allow_blank=True, default="")
    app_version = serializers.CharField(max_length=30, required=False, allow_blank=True, default="")


class LoginSerializer(serializers.Serializer):
    username = serializers.CharField(max_length=150)
    password = serializers.CharField(trim_whitespace=False)
    device_key = serializers.CharField(max_length=64)
    app_version = serializers.CharField(max_length=30, required=False, allow_blank=True, default="")


class DeviceSerializer(serializers.ModelSerializer):
    """Owner view of activated devices; only `name` and `is_active` are editable."""

    class Meta:
        model = Device
        fields = ["id", "device_id", "name", "is_active", "app_version", "last_login_at", "created_at"]
        read_only_fields = ["id", "device_id", "app_version", "last_login_at", "created_at"]


def session_payload(membership, device=None):
    """Everything the desktop needs after login / on `GET auth/me/`."""
    lab = membership.lab
    license_ = lab.license
    plan = license_.plan
    return {
        "user": UserSerializer(membership.user).data,
        "membership": {
            "id": membership.id,
            "role": membership.role,
            "is_owner": membership.is_owner,
            "can_view_costs": membership.sees_costs,
        },
        "lab": LabSettingsSerializer(lab).data,
        "plan": {
            "code": plan.code,
            "name": plan.name,
            "features": plan.features,
            "limits": plan.limits,
            "expires_on": license_.expires_on.isoformat() if license_.expires_on else None,
        },
        "device": {"id": device.id, "name": device.name} if device else None,
    }
