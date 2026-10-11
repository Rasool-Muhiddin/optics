from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import include, path

from apps.accounts.urls import auth_urlpatterns, desktop_urlpatterns

api_v1 = [
    path("", include("apps.core.urls")),
    path("desktop/", include(desktop_urlpatterns)),
    path("auth/", include(auth_urlpatterns)),
    path("lab/", include("apps.labs.urls")),
]

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/v1/", include(api_v1)),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
