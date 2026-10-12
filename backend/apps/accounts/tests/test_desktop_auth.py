import datetime

from django.utils import timezone

from apps.accounts.models import AuthToken, Device
from apps.core.testing import PASSWORD, LabAPITestCase, make_device, make_lab, make_member, make_plan
from apps.labs.models import LabUser

ACTIVATE = "/api/v1/desktop/activate/"
LOGIN = "/api/v1/desktop/login/"
ME = "/api/v1/auth/me/"
LOGOUT = "/api/v1/auth/logout/"


class ActivationTests(LabAPITestCase):
    def setUp(self):
        super().setUp()
        self.lab = make_lab("Al-Noor", plan=make_plan(max_devices=2))

    def _activate(self, code=None, device_id="pc-1", **extra):
        payload = {"activation_code": code or self.lab.activation_code, "device_id": device_id, **extra}
        return self.client.post(ACTIVATE, payload)

    def test_activation_creates_device_and_returns_key(self):
        response = self._activate(device_name="Reception PC", app_version="0.1.0")
        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(body["lab"], {"id": self.lab.id, "name": "Al-Noor"})
        self.assertTrue(body["device_key"])
        device = Device.objects.get(lab=self.lab, device_id="pc-1")
        self.assertEqual(device.name, "Reception PC")
        self.assertNotEqual(device.key_digest, body["device_key"])

    def test_activation_code_is_case_and_dash_insensitive(self):
        code = self.lab.activation_code
        messy = f"{code[:4].lower()}-{code[4:8]} {code[8:]}"
        self.assertEqual(self._activate(code=messy).status_code, 201)

    def test_invalid_code(self):
        response = self._activate(code="NOPE")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["code"], "invalid_activation_code")

    def test_device_limit(self):
        self._activate(device_id="pc-1")
        self._activate(device_id="pc-2")
        response = self._activate(device_id="pc-3")
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["code"], "device_limit_reached")

    def test_reactivating_same_device_reuses_slot_and_rotates_key(self):
        first = self._activate(device_id="pc-1").json()["device_key"]
        self._activate(device_id="pc-2")
        second = self._activate(device_id="pc-1")
        self.assertEqual(second.status_code, 201)
        self.assertNotEqual(first, second.json()["device_key"])
        self.assertEqual(Device.objects.filter(lab=self.lab).count(), 2)

    def test_expired_or_inactive_lab_cannot_activate(self):
        expired = make_lab(expires_on=timezone.localdate() - datetime.timedelta(days=1))
        self.assertEqual(self._activate(code=expired.activation_code).json()["code"], "license_expired")
        inactive = make_lab(is_active=False)
        self.assertEqual(self._activate(code=inactive.activation_code).json()["code"], "lab_inactive")

    def test_missing_fields(self):
        response = self.client.post(ACTIVATE, {})
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["code"], "validation_error")


class LoginTests(LabAPITestCase):
    def setUp(self):
        super().setUp()
        self.lab = make_lab("Al-Noor", plan=make_plan(doctor_linking=True, max_users=4))
        self.owner = make_member(self.lab, LabUser.Role.OWNER, username="owner")
        self.device, self.device_key = make_device(self.lab, name="PC 1")

    def _login(self, username="owner", password=PASSWORD, device_key=None):
        return self.client.post(
            LOGIN, {"username": username, "password": password, "device_key": device_key or self.device_key}
        )

    def test_login_returns_token_and_session(self):
        response = self._login()
        self.assertEqual(response.status_code, 200, response.content)
        body = response.json()
        self.assertTrue(body["token"])
        self.assertEqual(body["user"]["username"], "owner")
        self.assertEqual(body["membership"]["role"], "owner")
        self.assertTrue(body["membership"]["can_view_costs"])
        self.assertEqual(body["lab"]["id"], self.lab.id)
        self.assertNotIn("activation_code", body["lab"])
        self.assertEqual(body["plan"]["features"], {"doctor_linking": True, "report_export": False})
        self.assertEqual(body["plan"]["limits"]["max_users"], 4)
        self.assertEqual(body["device"]["id"], self.device.id)
        self.device.refresh_from_db()
        self.assertIsNotNone(self.device.last_login_at)

    def test_token_works_for_me_and_logout_revokes_it(self):
        token = self._login().json()["token"]
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token}")
        me = self.client.get(ME)
        self.assertEqual(me.status_code, 200)
        self.assertEqual(me.json()["device"]["id"], self.device.id)
        self.assertEqual(self.client.post(LOGOUT).status_code, 204)
        self.assertEqual(self.client.get(ME).status_code, 401)

    def test_logout_only_revokes_this_device(self):
        other_device, other_key = make_device(self.lab)
        token_1 = self._login().json()["token"]
        token_2 = self._login(device_key=other_key).json()["token"]
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token_1}")
        self.client.post(LOGOUT)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token_2}")
        self.assertEqual(self.client.get(ME).status_code, 200)

    def test_wrong_password(self):
        response = self._login(password="nope")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["code"], "invalid_credentials")
        self.assertFalse(AuthToken.objects.exists())

    def test_unknown_or_inactive_device(self):
        self.assertEqual(self._login(device_key="unknown").json()["code"], "device_not_activated")
        self.device.is_active = False
        self.device.save()
        response = self._login()
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["code"], "device_not_activated")

    def test_user_of_another_lab_cannot_login_on_this_device(self):
        make_member(make_lab(), LabUser.Role.OWNER, username="foreigner")
        response = self._login(username="foreigner")
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["code"], "device_lab_mismatch")

    def test_inactive_member_cannot_login(self):
        make_member(self.lab, username="gone", is_active=False)
        self.assertEqual(self._login(username="gone").json()["code"], "membership_inactive")

    def test_expired_license_cannot_login(self):
        license_ = self.lab.license
        license_.expires_on = timezone.localdate() - datetime.timedelta(days=1)
        license_.save()
        self.assertEqual(self._login().json()["code"], "license_expired")

    def test_staff_costs_flag(self):
        make_member(self.lab, username="cashier")
        make_member(self.lab, username="senior", can_view_costs=True)
        self.assertFalse(self._login(username="cashier").json()["membership"]["can_view_costs"])
        self.assertTrue(self._login(username="senior").json()["membership"]["can_view_costs"])

    def test_inventory_permission_in_session(self):
        make_member(self.lab, username="stock1", can_manage_inventory=True)
        make_member(self.lab, username="plain1")
        stock = self._login(username="stock1").json()["membership"]
        self.assertEqual((stock["can_manage_inventory"], stock["can_view_costs"]), (True, False))
        self.assertFalse(self._login(username="plain1").json()["membership"]["can_manage_inventory"])

    def test_activation_then_login_end_to_end(self):
        key = self.client.post(
            ACTIVATE, {"activation_code": self.lab.activation_code, "device_id": "new-pc"}
        ).json()["device_key"]
        self.assertEqual(self._login(device_key=key).status_code, 200)

    def test_reactivation_logs_out_old_sessions_of_that_device(self):
        token = self._login().json()["token"]
        self.client.post(ACTIVATE, {"activation_code": self.lab.activation_code, "device_id": self.device.device_id})
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token}")
        self.assertEqual(self.client.get(ME).status_code, 401)
