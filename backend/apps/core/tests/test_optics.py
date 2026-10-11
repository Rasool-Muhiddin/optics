from decimal import Decimal as D

from django.test import SimpleTestCase

from apps.core.optics import PowerError, check_add, check_axis, check_cyl, check_sph, to_minus_cyl, transpose


class PowerValidationTests(SimpleTestCase):
    def test_sph_range_and_step(self):
        self.assertEqual(check_sph("-2.25"), D("-2.25"))
        self.assertEqual(check_sph(30), D("30"))
        for bad in ("-30.25", "2.10", "abc", None):
            with self.assertRaises(PowerError) as ctx:
                check_sph(bad)
            self.assertEqual(ctx.exception.code, "invalid_sph")

    def test_cyl_and_add(self):
        self.assertEqual(check_cyl("-10"), D("-10"))
        with self.assertRaises(PowerError):
            check_cyl("-10.25")
        self.assertEqual(check_add("0.50"), D("0.50"))
        for bad in ("0.25", "4.25", "1.10"):
            with self.assertRaises(PowerError):
                check_add(bad)

    def test_axis(self):
        self.assertEqual(check_axis(180), 180)
        self.assertEqual(check_axis("90"), 90)
        for bad in (0, 181, "12.5", True, None, "x"):
            with self.assertRaises(PowerError) as ctx:
                check_axis(bad)
            self.assertEqual(ctx.exception.code, "invalid_axis")


class TranspositionTests(SimpleTestCase):
    def test_plus_to_minus(self):
        self.assertEqual(transpose("-1.00", "+2.00", 90), (D("1.00"), D("-2.00"), 180))
        self.assertEqual(transpose("+2.50", "+1.25", 135), (D("3.75"), D("-1.25"), 45))

    def test_minus_to_plus_round_trip(self):
        sph, cyl, axis = transpose("-2.00", "-0.75", 10)
        self.assertEqual((sph, cyl, axis), (D("-2.75"), D("0.75"), 100))
        self.assertEqual(transpose(sph, cyl, axis), (D("-2.00"), D("-0.75"), 10))

    def test_zero_cyl(self):
        self.assertEqual(transpose("-1.00", "0", None), (D("-1.00"), D("0.00"), None))

    def test_to_minus_cyl_keeps_minus_form(self):
        self.assertEqual(to_minus_cyl(D("-1"), D("-0.5"), 20), (D("-1"), D("-0.5"), 20))
        self.assertEqual(to_minus_cyl(D("-1"), D("0.5"), 20), (D("-0.50"), D("-0.50"), 110))
