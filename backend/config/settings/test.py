"""Settings for the test run (`pytest`): local settings + a fast password hasher."""

from .local import *  # noqa: F403

PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]
