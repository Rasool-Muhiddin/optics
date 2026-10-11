from django.conf import settings
from django.test import SimpleTestCase


class SettingsTests(SimpleTestCase):
    def test_every_app_is_installed(self):
        for app in [
            "core", "accounts", "labs", "billing", "catalog", "inventory", "patients",
            "sales", "jobs", "purchasing", "doctors", "reports", "app_updates",
        ]:
            self.assertIn(f"apps.{app}", settings.INSTALLED_APPS)

    def test_api_defaults(self):
        rf = settings.REST_FRAMEWORK
        self.assertIn("rest_framework.authentication.TokenAuthentication", rf["DEFAULT_AUTHENTICATION_CLASSES"])
        self.assertEqual(rf["DEFAULT_PERMISSION_CLASSES"], ["rest_framework.permissions.IsAuthenticated"])
        self.assertEqual(rf["DEFAULT_PAGINATION_CLASS"], "apps.core.pagination.StandardPagination")
        self.assertIn("django_filters.rest_framework.DjangoFilterBackend", rf["DEFAULT_FILTER_BACKENDS"])
