from django.contrib.auth.models import AbstractUser


class User(AbstractUser):
    """
    Custom user model, defined from day one so it can grow without a painful swap.

    Lab membership (`labs.LabUser`) and doctor profiles (`doctors.DoctorProfile`)
    attach to this model in later phases.
    """

    class Meta:
        verbose_name = "user"
        verbose_name_plural = "users"
