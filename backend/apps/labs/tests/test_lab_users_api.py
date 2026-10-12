from django.contrib.auth import get_user_model

from apps.core.testing import LabAPITestCase, make_lab, make_member, make_plan
from apps.labs.models import LabUser

URL = "/api/v1/lab/users/"


class LabUserApiTests(LabAPITestCase):
    def setUp(self):
        super().setUp()
        self.lab = make_lab(plan=make_plan(max_users=3))
        self.owner = make_member(self.lab, LabUser.Role.OWNER, username="owner")
        self.login_as(self.owner)

    def _create(self, username="cashier", **extra):
        payload = {"username": username, "password": "Cash1er-Pass!", "first_name": "علي", **extra}
        return self.client.post(URL, payload)

    def test_owner_creates_staff_with_login(self):
        response = self._create(role="staff")
        self.assertEqual(response.status_code, 201, response.content)
        self.assertNotIn("password", response.json())
        user = get_user_model().objects.get(username="cashier")
        self.assertTrue(user.check_password("Cash1er-Pass!"))
        self.assertEqual(user.first_name, "علي")
        self.assertEqual(user.lab_membership.lab, self.lab)

    def test_password_required_and_validated(self):
        self.assertEqual(self.client.post(URL, {"username": "x"}).json()["code"], "validation_error")
        response = self._create(password="123")
        self.assertIn("password", response.json()["errors"])

    def test_duplicate_username(self):
        make_member(make_lab(), username="taken")
        response = self._create(username="TAKEN")
        self.assertEqual(response.status_code, 400)
        self.assertIn("username", response.json()["errors"])

    def test_user_limit(self):
        self._create(username="u1")
        self._create(username="u2")
        response = self._create(username="u3")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["code"], "user_limit_reached")

    def test_inactive_users_do_not_count_and_reactivation_is_limited(self):
        self._create(username="u1")
        u2 = self._create(username="u2").json()
        self.client.patch(f"{URL}{u2['id']}/", {"is_active": False})
        self.assertEqual(self._create(username="u3").status_code, 201)
        response = self.client.patch(f"{URL}{u2['id']}/", {"is_active": True})
        self.assertEqual(response.json()["code"], "user_limit_reached")

    def test_update_role_and_reset_password(self):
        staff = make_member(self.lab, username="s1")
        response = self.client.patch(f"{URL}{staff.id}/", {"can_view_costs": True, "password": "N3w-Passw0rd!"})
        self.assertEqual(response.status_code, 200, response.content)
        staff.refresh_from_db()
        self.assertTrue(staff.can_view_costs)
        self.assertTrue(staff.user.check_password("N3w-Passw0rd!"))

    def test_owner_cannot_demote_or_disable_self(self):
        for payload in [{"role": "staff"}, {"is_active": False}]:
            response = self.client.patch(f"{URL}{self.owner.id}/", payload)
            self.assertEqual(response.status_code, 400)
            self.assertEqual(response.json()["code"], "cannot_modify_self")

    def test_no_hard_delete(self):
        staff = make_member(self.lab)
        self.assertEqual(self.client.delete(f"{URL}{staff.id}/").status_code, 405)

    def test_filter_by_role(self):
        make_member(self.lab)
        response = self.client.get(URL, {"role": "owner"})
        self.assertEqual(response.json()["count"], 1)


class LabSettingsApiTests(LabAPITestCase):
    def test_owner_updates_print_settings(self):
        lab = make_lab()
        self.login_as(make_member(lab, LabUser.Role.OWNER))
        response = self.client.patch("/api/v1/lab/", {"phone": "07700000000", "print_header": "فحص النظر"})
        self.assertEqual(response.status_code, 200, response.content)
        lab.refresh_from_db()
        self.assertEqual(lab.print_header, "فحص النظر")
        self.assertNotIn("activation_code", response.json())


class UsersScreenApiTests(LabAPITestCase):
    def setUp(self):
        super().setUp()
        from apps.core.testing import make_device

        self.lab = make_lab(plan=make_plan(max_users=2, max_devices=2))
        self.owner = make_member(self.lab, LabUser.Role.OWNER, username="boss")
        self.device, _ = make_device(self.lab, name="PC 1")
        self.login_as(self.owner, device=self.device)

    def test_phone_flags_and_usage(self):
        response = self.client.post(URL, {
            "username": "sara", "password": "Sara-Pass-123", "first_name": "سارة", "phone": "0770",
            "can_manage_inventory": True,
        })
        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual((body["phone"], body["can_manage_inventory"], body["can_view_costs"]), ("0770", True, False))
        usage = self.client.get("/api/v1/lab/usage/").json()
        self.assertEqual(usage, {"users": 2, "max_users": 2, "devices": 1, "max_devices": 2})
        third = self.client.post(URL, {"username": "x3", "password": "X3-Pass-12345"})
        self.assertEqual(third.json()["code"], "user_limit_reached")

    def test_password_reset_and_deactivation_end_sessions(self):
        from apps.accounts.models import AuthToken

        staff = make_member(self.lab, username="cash")
        AuthToken.issue(staff.user, self.device)
        self.client.patch(f"{URL}{staff.id}/", {"password": "N3w-Passw0rd!"})
        self.assertFalse(AuthToken.objects.filter(user=staff.user).exists())
        AuthToken.issue(staff.user, self.device)
        self.client.patch(f"{URL}{staff.id}/", {"is_active": False})
        self.assertFalse(AuthToken.objects.filter(user=staff.user).exists())

    def test_revoking_a_device_deletes_its_tokens_and_reactivation_respects_limit(self):
        from apps.accounts.models import AuthToken
        from apps.core.testing import make_device

        other, _ = make_device(self.lab, name="PC 2")
        staff = make_member(self.lab, username="cash2")
        AuthToken.issue(staff.user, other)
        response = self.client.patch(f"/api/v1/lab/devices/{other.id}/", {"is_active": False})
        self.assertFalse(response.json()["is_active"])
        self.assertFalse(AuthToken.objects.filter(device=other).exists())
        make_device(self.lab, name="PC 3")
        response = self.client.patch(f"/api/v1/lab/devices/{other.id}/", {"is_active": True})
        self.assertEqual(response.json()["code"], "device_limit_reached")

    def test_staff_cannot_read_usage(self):
        self.login_as(make_member(self.lab))
        self.assertEqual(self.client.get("/api/v1/lab/usage/").json()["code"], "owner_required")
