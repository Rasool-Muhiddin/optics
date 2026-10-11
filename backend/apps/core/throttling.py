from rest_framework.throttling import ScopedRateThrottle

from .client_ip import get_client_ip


class ClientIPScopedRateThrottle(ScopedRateThrottle):
    """`ScopedRateThrottle` keyed by the real client IP (see `apps.core.client_ip`)."""

    def get_ident(self, request):
        return get_client_ip(request)
