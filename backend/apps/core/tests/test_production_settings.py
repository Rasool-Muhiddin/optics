"""Production settings stay deployable: `check --deploy` is clean and static files collect."""

import os
import secrets
import subprocess
import sys
import tempfile
from pathlib import Path

from django.test import SimpleTestCase

BACKEND = Path(__file__).resolve().parents[3]


class ProductionSettingsTests(SimpleTestCase):
    def _run(self, *args, tmp):
        env = {
            **os.environ,
            "DJANGO_SETTINGS_MODULE": "config.settings.production",
            "SECRET_KEY": secrets.token_urlsafe(60),
            "ALLOWED_HOSTS": "optics-api.tera-software1.com",
            "CSRF_TRUSTED_ORIGINS": "https://optics-api.tera-software1.com",
            "DATABASE_URL": f"sqlite:///{tmp}/prod.sqlite3",
            "STATIC_ROOT": f"{tmp}/static",
            "MEDIA_ROOT": f"{tmp}/media",
            "ADMIN_URL": "tera-admin/",
        }
        return subprocess.run(
            [sys.executable, "manage.py", *args], cwd=BACKEND, env=env, capture_output=True, text=True,
            timeout=120,
        )

    def test_deploy_check_is_clean(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = self._run("check", "--deploy", "--fail-level", "WARNING", tmp=tmp)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_collectstatic_writes_admin_assets(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = self._run("collectstatic", "--noinput", tmp=tmp)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((Path(tmp) / "static" / "admin" / "css" / "base.css").exists())

    def test_production_requires_secrets(self):
        env = {k: v for k, v in os.environ.items() if k not in ("SECRET_KEY", "DATABASE_URL", "ALLOWED_HOSTS")}
        env["DJANGO_SETTINGS_MODULE"] = "config.settings.production"
        result = subprocess.run(
            [sys.executable, "manage.py", "check"], cwd=BACKEND, env=env, capture_output=True, text=True,
            timeout=120,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SECRET_KEY", result.stderr)
