import datetime

from django.utils import timezone

from apps.core.testing import LabAPITestCase, make_lab, make_member, make_plan
from apps.labs.models import LabUser


class LabAccessTests(LabAPITestCase):
    url = "/api/v1/auth/me/"

    def test_anonymous_is_rejected(self):
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, 401)

    def test_user_without_lab_is_rejected(self):
        from django.contrib.auth import get_user_model

        from apps.accounts.models import AuthToken

        user = get_user_model().objects.create_user(username="doctor1", password="x")
        _, key = AuthToken.issue(user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {key}")
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["code"], "no_lab_membership")

    def test_inactive_membership_is_rejected(self):
        member = make_member(make_lab(), is_active=False)
        self.login_as(member)
        self.assertEqual(self.client.get(self.url).json()["code"], "membership_inactive")

    def test_inactive_lab_is_rejected(self):
        member = make_member(make_lab(is_active=False))
        self.login_as(member)
        self.assertEqual(self.client.get(self.url).json()["code"], "lab_inactive")

    def test_lab_without_license_is_rejected(self):
        member = make_member(make_lab(license=False))
        self.login_as(member)
        self.assertEqual(self.client.get(self.url).json()["code"], "no_license")

    def test_expired_license_is_rejected(self):
        yesterday = timezone.localdate() - datetime.timedelta(days=1)
        member = make_member(make_lab(expires_on=yesterday))
        self.login_as(member)
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["code"], "license_expired")


class OwnerOnlyTests(LabAPITestCase):
    def setUp(self):
        super().setUp()
        self.lab = make_lab()
        self.staff = make_member(self.lab)
        self.login_as(self.staff)

    def test_staff_cannot_manage_users_or_devices(self):
        for url in ["/api/v1/lab/users/", "/api/v1/lab/devices/"]:
            response = self.client.get(url)
            self.assertEqual(response.status_code, 403)
            self.assertEqual(response.json()["code"], "owner_required")

    def test_staff_reads_but_cannot_edit_lab_settings(self):
        self.assertEqual(self.client.get("/api/v1/lab/").status_code, 200)
        response = self.client.patch("/api/v1/lab/", {"name": "x"})
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["code"], "owner_required")


class FeatureFlagTests(LabAPITestCase):
    def _view(self, flag):
        from rest_framework.response import Response
        from rest_framework.views import APIView

        from apps.core.permissions import requires_feature

        class _Gated(APIView):
            permission_classes = [requires_feature(flag)]

            def get(self, request):
                return Response({"ok": True})

        return _Gated.as_view()

    def _get(self, member, flag):
        from rest_framework.test import APIRequestFactory

        from apps.accounts.models import AuthToken

        _, key = AuthToken.issue(member.user)
        request = APIRequestFactory().get("/x/", HTTP_AUTHORIZATION=f"Token {key}")
        return self._view(flag)(request)

    def test_feature_in_plan_is_allowed(self):
        member = make_member(make_lab(plan=make_plan(doctor_linking=True)), LabUser.Role.OWNER)
        self.assertEqual(self._get(member, "doctor_linking").status_code, 200)

    def test_feature_not_in_plan_is_denied(self):
        member = make_member(make_lab(plan=make_plan(doctor_linking=False)), LabUser.Role.OWNER)
        response = self._get(member, "doctor_linking")
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.data["code"], "feature_not_in_plan")

    def test_unknown_flag_fails_loudly(self):
        from apps.core.permissions import requires_feature

        with self.assertRaises(ValueError):
            requires_feature("teleportation")
