"""
Shared permission classes.

`LabAccess` is the gate for every lab-scoped endpoint: it resolves the request's lab from
the token's user and blocks disabled memberships, disabled labs and invalid licenses.
"""

from rest_framework import exceptions
from rest_framework.permissions import SAFE_METHODS, AllowAny, BasePermission, IsAuthenticated  # noqa: F401

from .tenancy import check_lab_access, get_membership


class LabAccess(BasePermission):
    """Authenticated lab member with an active lab and a valid license. Sets `request.lab`."""

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        membership = getattr(request, "lab_user", None) or get_membership(request.user)
        check_lab_access(membership)
        request.lab_user = membership
        request.lab = membership.lab
        return True

    def has_object_permission(self, request, view, obj):
        # Defense in depth: querysets are already lab-filtered.
        lab_id = getattr(obj, "lab_id", None)
        return lab_id is None or lab_id == request.lab.id


class IsLabOwner(LabAccess):
    """Lab access + `owner` role."""

    def has_permission(self, request, view):
        super().has_permission(request, view)
        if not request.lab_user.is_owner:
            raise exceptions.PermissionDenied("Only the lab owner can do this.", code="owner_required")
        return True


class IsLabOwnerOrReadOnly(LabAccess):
    """Any lab member may read; only the owner may write."""

    def has_permission(self, request, view):
        super().has_permission(request, view)
        if request.method not in SAFE_METHODS and not request.lab_user.is_owner:
            raise exceptions.PermissionDenied("Only the lab owner can do this.", code="owner_required")
        return True


def requires_feature(flag):
    """
    Permission class gating an endpoint by a plan feature flag (see `apps.billing.features`):
    `permission_classes = [requires_feature("doctor_linking")]`.
    """
    from apps.billing.features import FEATURE_FLAGS

    if flag not in FEATURE_FLAGS:
        raise ValueError(f"Unknown feature flag: {flag}")

    class RequiresFeature(LabAccess):
        def has_permission(self, request, view):
            super().has_permission(request, view)
            if not request.lab.license.plan.has_feature(flag):
                raise exceptions.PermissionDenied(
                    f"Feature '{flag}' is not included in the lab's plan.", code="feature_not_in_plan"
                )
            return True

    RequiresFeature.__name__ = f"RequiresFeature_{flag}"
    return RequiresFeature
