"""
Lab-scoped base viewsets. Every endpoint over a `LabScopedModel` must use one of these,
so tenant isolation is enforced in one place (a test walks the URLconf to check it).
"""

from rest_framework import mixins, serializers, viewsets

from .permissions import LabAccess


class LabScopedMixin:
    """
    - `get_queryset()` only ever returns rows of `request.lab` (other labs' ids → 404).
    - `perform_create()` sets `lab` (and `created_by` when the model has it) server-side;
      any client-sent `lab` is ignored.
    """

    permission_classes = [LabAccess]

    def get_queryset(self):
        queryset = super().get_queryset()
        lab = getattr(self.request, "lab", None)
        if lab is None:
            return queryset.none()
        return queryset.filter(lab=lab)

    def perform_create(self, serializer):
        extra = {"lab": self.request.lab}
        model = serializer.Meta.model if hasattr(serializer, "Meta") else None
        if model is not None and any(f.name == "created_by" for f in model._meta.get_fields()):
            extra["created_by"] = self.request.user
        serializer.save(**extra)


class LabScopedViewSet(LabScopedMixin, viewsets.ModelViewSet):
    """Full CRUD. Business records should drop `destroy` (no hard deletes, CLAUDE.md §10)."""


class LabScopedReadOnlyViewSet(LabScopedMixin, viewsets.ReadOnlyModelViewSet):
    pass


class LabScopedNoDeleteViewSet(
    LabScopedMixin,
    mixins.CreateModelMixin,
    mixins.RetrieveModelMixin,
    mixins.UpdateModelMixin,
    mixins.ListModelMixin,
    viewsets.GenericViewSet,
):
    """CRUD without hard delete — deactivate/cancel via update instead."""


class LabScopedPrimaryKeyRelatedField(serializers.PrimaryKeyRelatedField):
    """
    FK field to another lab-scoped model: only ids of the request's lab are accepted,
    so lab A can never point a row at lab B's data.
    """

    def get_queryset(self):
        queryset = super().get_queryset()
        request = self.context.get("request")
        lab = getattr(request, "lab", None)
        if lab is None:
            return queryset.none()
        return queryset.filter(lab=lab)
