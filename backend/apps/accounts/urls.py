from django.urls import path

from .views import ActivateView, LoginView, LogoutView, MeView

desktop_urlpatterns = [
    path("activate/", ActivateView.as_view(), name="desktop-activate"),
    path("login/", LoginView.as_view(), name="desktop-login"),
]

auth_urlpatterns = [
    path("me/", MeView.as_view(), name="auth-me"),
    path("logout/", LogoutView.as_view(), name="auth-logout"),
]
