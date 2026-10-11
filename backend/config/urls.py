from django.contrib import admin
from django.urls import include, path

api_v1 = [
    path("", include("apps.core.urls")),
]

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/v1/", include(api_v1)),
]
