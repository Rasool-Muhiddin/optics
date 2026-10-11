from django.contrib.auth import get_user_model
from django.test import TestCase

from apps.core.testing import make_device, make_lab, make_member


class AdminSmokeTests(TestCase):
    """Every P1 admin page renders for Tera's superuser."""

    def setUp(self):
        admin = get_user_model().objects.create_superuser("tera", "t@example.com", "pass")
        self.client.force_login(admin)
        self.lab = make_lab()
        make_member(self.lab)
        make_device(self.lab)

    def test_changelists_and_change_pages(self):
        for model in ["labs/lab", "labs/labuser", "billing/plan", "billing/license",
                      "accounts/user", "accounts/device", "accounts/authtoken"]:
            response = self.client.get(f"/admin/{model}/")
            self.assertEqual(response.status_code, 200, model)
        self.assertEqual(self.client.get(f"/admin/labs/lab/{self.lab.id}/change/").status_code, 200)
        self.assertEqual(self.client.get("/admin/labs/lab/add/").status_code, 200)


class CreateLabCommandTests(TestCase):
    def test_creates_lab_owner_and_license(self):
        from io import StringIO

        from django.core.management import call_command

        from apps.labs.models import Lab, LabUser

        out = StringIO()
        call_command("create_lab", "Al-Noor", "noor_owner", "Pass-1234!", stdout=out)
        lab = Lab.objects.get(name="Al-Noor")
        self.assertIn(lab.activation_code, out.getvalue())
        self.assertTrue(lab.license.is_valid())
        self.assertTrue(LabUser.objects.get(lab=lab, user__username="noor_owner").is_owner)
