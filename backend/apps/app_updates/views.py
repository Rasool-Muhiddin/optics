from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.core.throttling import ClientIPScopedRateThrottle

from .models import DesktopAppVersion, version_key


class LatestVersionView(APIView):
    """
    `GET /api/v1/desktop/latest-version/?platform=windows&version=1.0.0` (public: the app checks
    before login). → `{available: false}` or the newest release with `update_available`
    (newer than `version`) and `mandatory` (flagged, or `version` < `min_supported_version`).
    """

    authentication_classes = []
    permission_classes = [AllowAny]
    throttle_classes = [ClientIPScopedRateThrottle]
    throttle_scope = "desktop_update"

    def get(self, request):
        platform = request.query_params.get("platform") or DesktopAppVersion.Platform.WINDOWS
        current = request.query_params.get("version") or "0"
        release = DesktopAppVersion.latest(platform)
        if release is None:
            return Response({"available": False, "update_available": False})
        newer = version_key(release.version) > version_key(current)
        too_old = bool(release.min_supported_version) and version_key(current) < version_key(
            release.min_supported_version
        )
        url = request.build_absolute_uri(release.installer.url) if release.installer else release.installer_url
        return Response({
            "available": True,
            "update_available": newer,
            "mandatory": newer and (release.is_mandatory or too_old),
            "version": release.version,
            "build_number": release.build_number,
            "url": url,
            "sha256": release.sha256,
            "size": release.size,
            "release_notes": release.release_notes,
            "published_at": release.published_at.isoformat(),
        })
