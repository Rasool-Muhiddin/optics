"""Production settings. Every secret comes from the environment; nothing has a default."""

from .base import *  # noqa: F403
from .base import env
from .proxies import CLOUDFLARE_IP_RANGES

DEBUG = False
SECRET_KEY = env("SECRET_KEY")
ALLOWED_HOSTS = env.list("ALLOWED_HOSTS")
DATABASES = {"default": env.db("DATABASE_URL")}
DATABASES["default"]["CONN_MAX_AGE"] = env.int("CONN_MAX_AGE", default=60)
DATABASES["default"]["CONN_HEALTH_CHECKS"] = True

# Files on disk, served by nginx (`location /static/` and `/media/`, see deploy/nginx/).
STATIC_ROOT = env.path("STATIC_ROOT", default="/srv/optics/static")
MEDIA_ROOT = env.path("MEDIA_ROOT", default="/srv/optics/media")

# Admin under a less guessable path (e.g. "tera-admin-7f3/"); Tera bookmarks it.
ADMIN_URL = env("ADMIN_URL", default="admin/")

CSRF_TRUSTED_ORIGINS = env.list("CSRF_TRUSTED_ORIGINS", default=[])

# nginx + Cloudflare terminate TLS in front of gunicorn.
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SECURE_SSL_REDIRECT = env.bool("SECURE_SSL_REDIRECT", default=True)
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
# One year once HTTPS works end to end (Cloudflare "Full (strict)"); subdomain only, so the
# pharmacy subdomains are not affected.
SECURE_HSTS_SECONDS = env.int("SECURE_HSTS_SECONDS", default=31536000)
SECURE_HSTS_INCLUDE_SUBDOMAINS = False
SECURE_HSTS_PRELOAD = False
# Deliberate: HSTS only for this API host (no subdomains, no preload list for the shared domain).
SILENCED_SYSTEM_CHECKS = ["security.W005", "security.W021"]
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = "same-origin"
X_FRAME_OPTIONS = "DENY"
SESSION_COOKIE_HTTPONLY = True

# Admin uploads of desktop installers: files above this go to a temp file, never memory.
FILE_UPLOAD_MAX_MEMORY_SIZE = 5 * 1024 * 1024

# gunicorn only sees nginx (loopback); nginx only sees Cloudflare. Trust exactly those
# hops so throttling keys on the real client (CF-Connecting-IP / X-Forwarded-For).
TRUSTED_PROXIES = env.list("TRUSTED_PROXIES", default=["127.0.0.1/32", "::1/128"])
if env.bool("TRUST_CLOUDFLARE", default=True):
    TRUSTED_PROXIES = TRUSTED_PROXIES + CLOUDFLARE_IP_RANGES

# stdout/stderr → journald (`journalctl -u optics-api`).
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {"plain": {"format": "%(asctime)s %(levelname)s %(name)s: %(message)s"}},
    "handlers": {"console": {"class": "logging.StreamHandler", "formatter": "plain"}},
    "root": {"handlers": ["console"], "level": env("LOG_LEVEL", default="INFO")},
    "loggers": {"django.security.DisallowedHost": {"level": "ERROR"}},
}
