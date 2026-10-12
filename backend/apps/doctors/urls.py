from django.urls import path
from rest_framework.routers import SimpleRouter

from .views import DoctorLinkViewSet, DoctorMeView, DoctorReferralViewSet, LabDoctorLinkViewSet, LabReferralViewSet

doctor_router = SimpleRouter()
doctor_router.register("links", DoctorLinkViewSet, basename="doctor-link")
doctor_router.register("referrals", DoctorReferralViewSet, basename="doctor-referral")

# `/api/v1/doctor/…` — doctor accounts.
doctor_urlpatterns = [
    path("me/", DoctorMeView.as_view(), name="doctor-me"),
    *doctor_router.urls,
]

lab_router = SimpleRouter()
lab_router.register("links", LabDoctorLinkViewSet, basename="lab-doctor-link")
lab_router.register("", LabReferralViewSet, basename="referral")

# `/api/v1/referrals/…` — the lab side (plan `doctor_linking`).
lab_urlpatterns = lab_router.urls
