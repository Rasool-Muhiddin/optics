from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from django.db import transaction
from rest_framework import serializers

from apps.billing.features import check_user_limit
from apps.core.exceptions import APIError

from .models import Lab, LabUser


class LabSettingsSerializer(serializers.ModelSerializer):
    """What the desktop needs about its lab (print header, currency…). No internal fields."""

    class Meta:
        model = Lab
        fields = [
            "id", "name", "phone", "address", "logo", "currency", "print_header", "print_footer",
            "max_discount_percent",
        ]
        read_only_fields = ["id"]


class LabUserSerializer(serializers.ModelSerializer):
    """
    Owner-managed lab users. Creating one also creates the login (`username` + `password`);
    `password` may be sent on update to reset it. No hard delete: set `is_active=false`.
    """

    username = serializers.CharField(source="user.username", max_length=150)
    first_name = serializers.CharField(source="user.first_name", max_length=150, required=False, allow_blank=True)
    last_name = serializers.CharField(source="user.last_name", max_length=150, required=False, allow_blank=True)
    password = serializers.CharField(write_only=True, required=False, trim_whitespace=False)
    user_id = serializers.IntegerField(source="user.id", read_only=True)

    class Meta:
        model = LabUser
        fields = [
            "id", "user_id", "username", "first_name", "last_name", "password",
            "role", "can_view_costs", "can_manage_inventory", "is_active", "created_at",
        ]
        read_only_fields = ["id", "user_id", "created_at"]

    def validate_username(self, value):
        users = get_user_model().objects.filter(username__iexact=value)
        if self.instance is not None:
            users = users.exclude(pk=self.instance.user_id)
        if users.exists():
            raise serializers.ValidationError("This username is taken.", code="username_taken")
        return value

    def validate_password(self, value):
        validate_password(value)
        return value

    def validate(self, attrs):
        request = self.context["request"]
        if self.instance is None and not attrs.get("password"):
            raise serializers.ValidationError({"password": "Required."}, code="required")
        if self.instance is not None and self.instance.pk == request.lab_user.pk:
            demoting = attrs.get("role", self.instance.role) != LabUser.Role.OWNER
            disabling = attrs.get("is_active", True) is False
            if demoting or disabling:
                raise APIError("You cannot demote or disable your own account.", code="cannot_modify_self")
        becomes_active = attrs.get("is_active", True) and (self.instance is None or not self.instance.is_active)
        if becomes_active:
            check_user_limit(
                request.lab,
                exclude_pk=self.instance.pk if self.instance else None,
                error_class=APIError,
            )
        return attrs

    @transaction.atomic
    def create(self, validated_data):
        user_data = validated_data.pop("user")
        password = validated_data.pop("password")
        user = get_user_model().objects.create_user(password=password, **user_data)
        return LabUser.objects.create(user=user, **validated_data)

    @transaction.atomic
    def update(self, instance, validated_data):
        user_data = validated_data.pop("user", {})
        password = validated_data.pop("password", None)
        user = instance.user
        for field, value in user_data.items():
            setattr(user, field, value)
        if password:
            user.set_password(password)
        user.save()
        return super().update(instance, validated_data)
