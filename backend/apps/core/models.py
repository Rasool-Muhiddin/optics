from django.db import models


class TimeStampedModel(models.Model):
    """Adds `created_at` / `updated_at` to every business model."""

    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


# `LabScopedModel` (abstract, `lab` FK + lab-filtered manager) is added in P1 together
# with the `labs.Lab` tenant model it points to.
