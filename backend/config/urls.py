from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import include, path

from apps.accounts.urls import auth_urlpatterns, desktop_urlpatterns
from apps.doctors.urls import doctor_urlpatterns, lab_urlpatterns as referral_urlpatterns
from apps.doctors.views import DoctorLoginView

api_v1 = [
    path("", include("apps.core.urls")),
    path("desktop/", include(desktop_urlpatterns)),
    path("desktop/doctor-login/", DoctorLoginView.as_view(), name="doctor-login"),
    path("auth/", include(auth_urlpatterns)),
    path("lab/", include("apps.labs.urls")),
    path("catalog/", include("apps.catalog.urls")),
    path("inventory/", include("apps.inventory.urls")),
    path("patients/", include("apps.patients.urls")),
    path("sales/", include("apps.sales.urls")),
    path("jobs/", include("apps.jobs.urls")),
    path("purchasing/", include("apps.purchasing.urls")),
    path("doctor/", include(doctor_urlpatterns)),
    path("referrals/", include(referral_urlpatterns)),
]

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/v1/", include(api_v1)),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
