from decimal import Decimal as D

from django.test import SimpleTestCase

from apps.patients.rx import RxError, clean_rx


def codes(data):
    try:
        clean_rx(data)
    except RxError as exc:
        return {field: code for field, (_, code) in exc.errors.items()}
    return {}


class RxValidationTests(SimpleTestCase):
    def test_valid_full_rx(self):
        out = clean_rx({
            "od_sph": "-2.25", "od_cyl": "-0.75", "od_axis": 180, "od_add": "2.00",
            "os_sph": "-2.00", "os_cyl": "0", "os_axis": 90,
            "pd_distance": "63", "pd_near": "60.5", "lens_coatings": ["blue_cut", "ar"],
        })
        self.assertEqual((out["od_sph"], out["od_cyl"], out["od_axis"]), (D("-2.25"), D("-0.75"), 180))
        self.assertIsNone(out["os_axis"])  # CYL 0 → no axis
        self.assertEqual(out["os_cyl"], D("0.00"))
        self.assertEqual(out["lens_coatings"], ["ar", "blue_cut"])

    def test_steps_and_ranges(self):
        self.assertEqual(codes({"od_sph": "-2.10"}), {"od_sph": "invalid_sph"})
        self.assertEqual(codes({"od_sph": "31"}), {"od_sph": "invalid_sph"})
        self.assertEqual(codes({"od_sph": "0", "od_cyl": "-10.25", "od_axis": 5}), {"od_cyl": "invalid_cyl"})
        self.assertEqual(codes({"od_sph": "0", "od_add": "0.25"}), {"od_add": "invalid_add"})
        self.assertEqual(codes({"od_sph": "0", "od_add": "4.25"}), {"od_add": "invalid_add"})

    def test_axis_required_iff_cyl(self):
        self.assertEqual(codes({"od_sph": "-1", "od_cyl": "-1"}), {"od_axis": "axis_required"})
        self.assertEqual(codes({"od_sph": "-1", "od_cyl": "-1", "od_axis": 0}), {"od_axis": "invalid_axis"})
        self.assertEqual(codes({"od_sph": "-1", "od_cyl": "-1", "od_axis": 181}), {"od_axis": "invalid_axis"})
        self.assertEqual(codes({"od_sph": "-1", "od_axis": 45}), {})

    def test_plus_cyl_is_stored_as_minus_cyl(self):
        out = clean_rx({"od_sph": "-1.00", "od_cyl": "+2.00", "od_axis": 90})
        self.assertEqual((out["od_sph"], out["od_cyl"], out["od_axis"]), (D("1.00"), D("-2.00"), 180))

    def test_sph_required_when_eye_used_and_one_eye_minimum(self):
        self.assertEqual(codes({"od_cyl": "-1", "od_axis": 10}), {"od_sph": "sph_required"})
        self.assertEqual(codes({}), {"od_sph": "rx_empty"})
        self.assertEqual(codes({"os_sph": "0"}), {})  # one eye only is fine

    def test_prism_needs_base(self):
        self.assertEqual(codes({"od_sph": "0", "od_prism": "1"}), {"od_base": "base_required"})
        self.assertEqual(codes({"od_sph": "0", "od_prism": "1", "od_base": "in"}), {})

    def test_pd_and_choices(self):
        self.assertEqual(codes({"od_sph": "0", "pd_distance": "30"}), {"pd_distance": "invalid_pd"})
        self.assertEqual(codes({"od_sph": "0", "pd_od": "31.5"}), {})
        self.assertEqual(codes({"od_sph": "0", "lens_index": "1.55"}), {"lens_index": "invalid_choice"})
