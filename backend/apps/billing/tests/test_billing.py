import datetime

from django.core.exceptions import ValidationError
from django.test import TestCase
from django.utils import timezone

from apps.billing.features import FEATURE_FLAGS
from apps.core.testing import make_device, make_lab, make_member, make_plan
from apps.labs.models import LabUser


class PlanTests(TestCase):
    def test_features_and_limits(self):
        plan = make_plan(report_export=True, max_users=2, max_devices=1)
        self.assertEqual(set(plan.features), set(FEATURE_FLAGS))
        self.assertTrue(plan.has_feature("report_export"))
        self.assertFalse(plan.has_feature("doctor_linking"))
        self.assertEqual(plan.limits, {"max_users": 2, "max_devices": 1})
        with self.assertRaises(ValueError):
            plan.has_feature("unknown")

    def test_every_flag_is_a_plan_field(self):
        from apps.billing.models import Plan

        for flag in FEATURE_FLAGS:
            self.assertIsNotNone(Plan._meta.get_field(flag))


class LicenseTests(TestCase):
    def test_validity_window(self):
        today = timezone.localdate()
        license_ = make_lab().license
        self.assertTrue(license_.is_valid())
        license_.expires_on = today
        self.assertTrue(license_.is_valid())
        license_.expires_on = today - datetime.timedelta(days=1)
        self.assertFalse(license_.is_valid())
        license_.expires_on = None
        license_.starts_on = today + datetime.timedelta(days=1)
        self.assertFalse(license_.is_valid())
        license_.starts_on = today
        license_.is_active = False
        self.assertFalse(license_.is_valid())


class AdminLimitTests(TestCase):
    """Limits also hold when Tera edits data in Django Admin (model `clean()`)."""

    def test_user_limit_in_model_clean(self):
        lab = make_lab(plan=make_plan(max_users=1))
        make_member(lab)
        extra = LabUser(lab=lab, user=make_member(make_lab()).user)
        with self.assertRaises(ValidationError):
            extra.clean()

    def test_zero_means_unlimited(self):
        lab = make_lab(plan=make_plan(max_devices=0))
        for _ in range(3):
            make_device(lab)
        from apps.accounts.models import Device

        Device(lab=lab, device_id="more").clean()

    def test_device_limit_in_model_clean(self):
        lab = make_lab(plan=make_plan(max_devices=1))
        make_device(lab)
        from apps.accounts.models import Device

        with self.assertRaises(ValidationError):
            Device(lab=lab, device_id="second").clean()
