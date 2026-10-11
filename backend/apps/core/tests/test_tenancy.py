"""
Tenant isolation: lab A can never read or touch lab B's data, whatever the client sends.
"""

from django.urls import URLPattern, URLResolver, get_resolver
from rest_framework import serializers
from rest_framework.test import APIRequestFactory

from apps.core.models import LabScopedModel
from apps.core.testing import LabAPITestCase, make_device, make_lab, make_member
from apps.core.viewsets import LabScopedMixin, LabScopedPrimaryKeyRelatedField
from apps.labs.models import LabUser


class LabIsolationTests(LabAPITestCase):
    def setUp(self):
        super().setUp()
        self.lab_a = make_lab("Lab A")
        self.lab_b = make_lab("Lab B")
        self.owner_a = make_member(self.lab_a, LabUser.Role.OWNER, username="owner_a")
        self.owner_b = make_member(self.lab_b, LabUser.Role.OWNER, username="owner_b")
        self.staff_b = make_member(self.lab_b, username="staff_b")
        self.device_b, _ = make_device(self.lab_b, name="PC B")
        self.login_as(self.owner_a)

    def test_list_users_only_returns_own_lab(self):
        response = self.client.get("/api/v1/lab/users/")
        self.assertEqual(response.status_code, 200)
        usernames = {row["username"] for row in response.json()["results"]}
        self.assertEqual(usernames, {"owner_a"})

    def test_cannot_retrieve_other_labs_user(self):
        response = self.client.get(f"/api/v1/lab/users/{self.staff_b.id}/")
        self.assertEqual(response.status_code, 404)

    def test_cannot_update_other_labs_user(self):
        response = self.client.patch(f"/api/v1/lab/users/{self.staff_b.id}/", {"is_active": False})
        self.assertEqual(response.status_code, 404)
        self.staff_b.refresh_from_db()
        self.assertTrue(self.staff_b.is_active)

    def test_search_cannot_reach_other_lab(self):
        response = self.client.get("/api/v1/lab/users/", {"search": "staff_b"})
        self.assertEqual(response.json()["count"], 0)

    def test_list_devices_only_returns_own_lab(self):
        response = self.client.get("/api/v1/lab/devices/")
        names = {row["name"] for row in response.json()["results"]}
        self.assertNotIn("PC B", names)

    def test_cannot_retrieve_or_disable_other_labs_device(self):
        self.assertEqual(self.client.get(f"/api/v1/lab/devices/{self.device_b.id}/").status_code, 404)
        response = self.client.patch(f"/api/v1/lab/devices/{self.device_b.id}/", {"is_active": False})
        self.assertEqual(response.status_code, 404)
        self.device_b.refresh_from_db()
        self.assertTrue(self.device_b.is_active)

    def test_lab_settings_are_the_tokens_lab(self):
        response = self.client.get("/api/v1/lab/", {"lab": self.lab_b.id})
        self.assertEqual(response.json()["id"], self.lab_a.id)
        self.client.patch("/api/v1/lab/", {"id": self.lab_b.id, "name": "Hacked"})
        self.lab_b.refresh_from_db()
        self.assertEqual(self.lab_b.name, "Lab B")

    def test_create_ignores_client_sent_lab(self):
        response = self.client.post(
            "/api/v1/lab/users/",
            {"username": "new_staff", "password": "An0ther-Pass!", "role": "staff", "lab": self.lab_b.id},
        )
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(LabUser.objects.get(user__username="new_staff").lab, self.lab_a)

    def test_me_returns_own_lab(self):
        self.assertEqual(self.client.get("/api/v1/auth/me/").json()["lab"]["id"], self.lab_a.id)


class LabScopedRelatedFieldTests(LabAPITestCase):
    def test_rejects_ids_from_another_lab(self):
        lab_a, lab_b = make_lab(), make_lab()
        member_a, member_b = make_member(lab_a), make_member(lab_b)

        class _Ser(serializers.Serializer):
            member = LabScopedPrimaryKeyRelatedField(queryset=LabUser.objects.all())

        request = APIRequestFactory().post("/x/")
        request.lab = lab_a
        ok = _Ser(data={"member": member_a.id}, context={"request": request})
        self.assertTrue(ok.is_valid(), ok.errors)
        bad = _Ser(data={"member": member_b.id}, context={"request": request})
        self.assertFalse(bad.is_valid())
        self.assertIn("member", bad.errors)


class ScopingGuardTests(LabAPITestCase):
    """Every API view over a lab-scoped model must go through `LabScopedMixin`."""

    def _views(self, resolver=None):
        for entry in (resolver or get_resolver()).url_patterns:
            if isinstance(entry, URLResolver):
                yield from self._views(entry)
            elif isinstance(entry, URLPattern):
                view_class = getattr(entry.callback, "cls", None)
                if view_class is not None:
                    yield view_class

    def test_lab_scoped_querysets_use_the_mixin(self):
        checked = 0
        for view_class in self._views():
            queryset = getattr(view_class, "queryset", None)
            if queryset is None or not issubclass(queryset.model, LabScopedModel):
                continue
            checked += 1
            self.assertTrue(
                issubclass(view_class, LabScopedMixin),
                f"{view_class.__name__} exposes {queryset.model.__name__} without LabScopedMixin",
            )
        self.assertGreater(checked, 0)
