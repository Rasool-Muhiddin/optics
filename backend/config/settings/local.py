"""Local development settings (`backend/.env.local` is read by base.py if present)."""

from .base import *  # noqa: F403
from .base import BASE_DIR, env

DEBUG = env.bool("DEBUG", default=True)
SECRET_KEY = env("SECRET_KEY", default="dev-insecure-secret-key-change-me")
ALLOWED_HOSTS = env.list("ALLOWED_HOSTS", default=["127.0.0.1", "localhost", "testserver"])
DATABASES = {
    "default": env.db("DATABASE_URL", default=f"sqlite:///{BASE_DIR / 'db.sqlite3'}"),
}

# The desktop app is the only API client; the browsable API helps while developing.
REST_FRAMEWORK["DEFAULT_RENDERER_CLASSES"] = [  # noqa: F405
    "rest_framework.renderers.JSONRenderer",
    "rest_framework.renderers.BrowsableAPIRenderer",
]
REST_FRAMEWORK["DEFAULT_AUTHENTICATION_CLASSES"] = [  # noqa: F405
    "rest_framework.authentication.TokenAuthentication",
    "rest_framework.authentication.SessionAuthentication",
]
