from django.urls import path

from apps.app_updates.views import LatestVersionView

from .views import ActivateView, LoginView, LogoutView, MeView

desktop_urlpatterns = [
    path("activate/", ActivateView.as_view(), name="desktop-activate"),
    path("login/", LoginView.as_view(), name="desktop-login"),
    path("latest-version/", LatestVersionView.as_view(), name="desktop-latest-version"),
]

auth_urlpatterns = [
    path("me/", MeView.as_view(), name="auth-me"),
    path("logout/", LogoutView.as_view(), name="auth-logout"),
]
