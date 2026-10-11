from unittest import mock

from django.db import connection
from django.urls import reverse
from rest_framework.test import APITestCase


class HealthEndpointTests(APITestCase):
    url = "/api/v1/health/"

    def test_url_is_stable(self):
        self.assertEqual(reverse("health"), self.url)

    def test_health_is_public_and_ok(self):
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["status"], "ok")
        self.assertEqual(response.json()["database"], "ok")
        self.assertIn("version", response.json())
        self.assertIn("server_time", response.json())

    def test_health_ignores_invalid_token(self):
        self.client.credentials(HTTP_AUTHORIZATION="Token not-a-real-token")
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, 200)

    def test_health_reports_database_outage(self):
        with mock.patch.object(connection, "ensure_connection", side_effect=Exception("down")):
            response = self.client.get(self.url)
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json()["status"], "degraded")

    def test_health_rejects_writes(self):
        response = self.client.post(self.url, {})
        self.assertEqual(response.status_code, 405)
        self.assertEqual(response.json()["code"], "method_not_allowed")
