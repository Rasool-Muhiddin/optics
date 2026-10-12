from rest_framework import exceptions
from rest_framework.permissions import BasePermission


class IsDoctor(BasePermission):
    """Authenticated user with an active `DoctorProfile`. Sets `request.doctor`."""

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        profile = getattr(request.user, "doctor_profile", None)
        if profile is None:
            raise exceptions.PermissionDenied("This account is not a doctor account.", code="not_a_doctor")
        if not profile.is_active:
            raise exceptions.PermissionDenied("This doctor account is disabled.", code="doctor_inactive")
        request.doctor = profile
        return True
