"""
Plan feature flags and limits. Add a flag here + a BooleanField on `Plan` (+ migration).

Gate endpoints with `apps.core.permissions.requires_feature("<flag>")`.
"""

FEATURE_FLAGS = ("doctor_linking", "report_export")


def check_user_limit(lab, *, exclude_pk=None, error_class):
    """Raise `error_class(..., code="user_limit_reached")` if one more active user exceeds the plan."""
    from apps.labs.models import LabUser

    license_ = getattr(lab, "license", None)
    limit = license_.plan.max_users if license_ else 0
    if not limit:
        return
    active = LabUser.objects.filter(lab=lab, is_active=True).exclude(pk=exclude_pk).count()
    if active >= limit:
        raise error_class(f"The plan allows at most {limit} active users.", code="user_limit_reached")


def check_device_limit(lab, *, exclude_pk=None, error_class):
    """Raise `error_class(..., code="device_limit_reached")` if one more active device exceeds the plan."""
    from apps.accounts.models import Device

    license_ = getattr(lab, "license", None)
    limit = license_.plan.max_devices if license_ else 0
    if not limit:
        return
    active = Device.objects.filter(lab=lab, is_active=True).exclude(pk=exclude_pk).count()
    if active >= limit:
        raise error_class(f"The plan allows at most {limit} active devices.", code="device_limit_reached")
