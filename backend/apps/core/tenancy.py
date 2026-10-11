"""
Resolves the tenant (lab) of a request.

The lab always comes from the authenticated user's `LabUser` membership — never from a
client-sent id. `LabAccess` stores it on the request as `request.lab` / `request.lab_user`.
"""

from django.core.exceptions import ObjectDoesNotExist
from rest_framework import exceptions


def get_membership(user):
    """The user's `LabUser` (with lab, license and plan loaded), or None."""
    if not user or not user.is_authenticated:
        return None
    from apps.labs.models import LabUser

    return (
        LabUser.objects.select_related("lab", "lab__license", "lab__license__plan")
        .filter(user=user)
        .first()
    )


def check_lab_access(membership):
    """Raises `PermissionDenied` with a stable `code` unless the membership may use the API."""
    if membership is None:
        raise exceptions.PermissionDenied("User is not a member of any lab.", code="no_lab_membership")
    if not membership.is_active:
        raise exceptions.PermissionDenied("Lab membership is disabled.", code="membership_inactive")
    lab = membership.lab
    if not lab.is_active:
        raise exceptions.PermissionDenied("Lab is disabled.", code="lab_inactive")
    try:
        license_ = lab.license
    except ObjectDoesNotExist:
        raise exceptions.PermissionDenied("Lab has no license.", code="no_license") from None
    if not license_.is_valid():
        raise exceptions.PermissionDenied("Lab license has expired.", code="license_expired")
