from rest_framework import exceptions
from rest_framework.authentication import TokenAuthentication

from .models import AuthToken, hash_secret


class DeviceTokenAuthentication(TokenAuthentication):
    """`Authorization: Token <key>` against `AuthToken` (per-device, digest-stored)."""

    keyword = "Token"

    def authenticate_credentials(self, key):
        token = (
            AuthToken.objects.select_related("user", "device")
            .filter(digest=hash_secret(key))
            .first()
        )
        if token is None:
            raise exceptions.AuthenticationFailed("Invalid token.")
        if not token.user.is_active:
            raise exceptions.AuthenticationFailed("User inactive or deleted.")
        if token.device_id and not token.device.is_active:
            raise exceptions.AuthenticationFailed("Device has been deactivated.", code="device_deactivated")
        return (token.user, token)
