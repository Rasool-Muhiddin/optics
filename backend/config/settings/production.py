"""Production settings. Every secret comes from the environment; nothing has a default."""

from .base import *  # noqa: F403
from .base import env
from .proxies import CLOUDFLARE_IP_RANGES

DEBUG = False
SECRET_KEY = env("SECRET_KEY")
ALLOWED_HOSTS = env.list("ALLOWED_HOSTS")
DATABASES = {"default": env.db("DATABASE_URL")}
DATABASES["default"]["CONN_MAX_AGE"] = env.int("CONN_MAX_AGE", default=60)

CSRF_TRUSTED_ORIGINS = env.list("CSRF_TRUSTED_ORIGINS", default=[])

# nginx + Cloudflare terminate TLS in front of gunicorn.
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SECURE_SSL_REDIRECT = env.bool("SECURE_SSL_REDIRECT", default=True)
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
SECURE_HSTS_SECONDS = env.int("SECURE_HSTS_SECONDS", default=0)
SECURE_CONTENT_TYPE_NOSNIFF = True

# gunicorn only sees nginx (loopback); nginx only sees Cloudflare. Trust exactly those
# hops so throttling keys on the real client (CF-Connecting-IP / X-Forwarded-For).
TRUSTED_PROXIES = env.list("TRUSTED_PROXIES", default=["127.0.0.1/32", "::1/128"])
if env.bool("TRUST_CLOUDFLARE", default=True):
    TRUSTED_PROXIES = TRUSTED_PROXIES + CLOUDFLARE_IP_RANGES

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {"console": {"class": "logging.StreamHandler"}},
    "root": {"handlers": ["console"], "level": "INFO"},
}
