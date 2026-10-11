from django.urls import path
from rest_framework.routers import SimpleRouter

from .views import EyeExamViewSet, PatientViewSet, PrescriptionViewSet, TransposeView

router = SimpleRouter()
router.register("exams", EyeExamViewSet, basename="exam")
router.register("prescriptions", PrescriptionViewSet, basename="prescription")
router.register("", PatientViewSet, basename="patient")

urlpatterns = [
    path("transpose/", TransposeView.as_view(), name="rx-transpose"),
    *router.urls,
]
