from django.urls import path
from rest_framework.routers import SimpleRouter

from apps.accounts.views import DeviceViewSet

from .views import LabSettingsView, LabUsageView, LabUserViewSet

router = SimpleRouter()
router.register("users", LabUserViewSet, basename="lab-user")
router.register("devices", DeviceViewSet, basename="lab-device")

urlpatterns = [
    path("", LabSettingsView.as_view(), name="lab-settings"),
    path("usage/", LabUsageView.as_view(), name="lab-usage"),
    *router.urls,
]
