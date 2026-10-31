"""gunicorn settings for optics-api.service (values can be overridden in .env.production)."""

import os

bind = "unix:/run/optics/gunicorn.sock"
umask = 0o007  # socket + uploaded files readable by the www-data group (nginx)

# The server is shared with the pharmacy backend: keep it small. 3 workers serve a few dozen
# labs comfortably (every request is short; long jobs do not exist).
workers = int(os.environ.get("GUNICORN_WORKERS", "3"))
timeout = int(os.environ.get("GUNICORN_TIMEOUT", "120"))
graceful_timeout = 30
keepalive = 5

# Recycle workers now and then so a slow memory leak can never take the server down.
max_requests = 1000
max_requests_jitter = 100

# Logs go to stdout/stderr → journald (`journalctl -u optics-api`).
accesslog = "-"
errorlog = "-"
loglevel = os.environ.get("GUNICORN_LOG_LEVEL", "info")
