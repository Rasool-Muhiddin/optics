from django.db import models


class TimeStampedModel(models.Model):
    """Adds `created_at` / `updated_at` to every business model."""

    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class LabScopedQuerySet(models.QuerySet):
    def for_lab(self, lab):
        """Rows owned by `lab` (a `labs.Lab` instance or id)."""
        return self.filter(lab=lab)


class LabScopedModel(TimeStampedModel):
    """
    Base for every lab-owned (tenant) row.

    API access goes through `apps.core.viewsets.LabScopedViewSet`, which filters by the
    lab of the request's token and sets `lab` on create — never filter by hand per view.
    """

    lab = models.ForeignKey(
        "labs.Lab",
        on_delete=models.PROTECT,
        related_name="%(app_label)s_%(class)s_set",
    )

    objects = LabScopedQuerySet.as_manager()

    class Meta:
        abstract = True
