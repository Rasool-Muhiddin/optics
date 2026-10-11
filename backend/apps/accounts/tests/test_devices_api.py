from apps.core.testing import LabAPITestCase, make_device, make_lab, make_member, make_plan
from apps.labs.models import LabUser

URL = "/api/v1/lab/devices/"


class DeviceApiTests(LabAPITestCase):
    def setUp(self):
        super().setUp()
        self.lab = make_lab(plan=make_plan(max_devices=2))
        self.owner = make_member(self.lab, LabUser.Role.OWNER)
        self.device, _ = make_device(self.lab, name="PC 1")
        self.login_as(self.owner, self.device)

    def test_owner_lists_and_renames(self):
        self.assertEqual(self.client.get(URL).json()["count"], 1)
        response = self.client.patch(f"{URL}{self.device.id}/", {"name": "Front desk", "device_id": "x"})
        self.assertEqual(response.status_code, 200)
        self.device.refresh_from_db()
        self.assertEqual(self.device.name, "Front desk")
        self.assertNotEqual(self.device.device_id, "x")

    def test_devices_cannot_be_created_or_deleted_via_api(self):
        self.assertEqual(self.client.post(URL, {"device_id": "x"}).status_code, 405)
        self.assertEqual(self.client.delete(f"{URL}{self.device.id}/").status_code, 405)

    def test_reactivation_respects_device_limit(self):
        make_device(self.lab)
        off, _ = make_device(self.lab, is_active=False)
        response = self.client.patch(f"{URL}{off.id}/", {"is_active": True})
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["code"], "device_limit_reached")
