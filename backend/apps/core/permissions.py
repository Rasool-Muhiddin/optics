"""
Shared permission classes.

Role-based permissions (owner / staff) and the lab-scoped base viewset arrive in P1
together with `labs.LabUser`.
"""

from rest_framework.permissions import AllowAny, IsAuthenticated  # noqa: F401
