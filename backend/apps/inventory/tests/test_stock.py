from decimal import Decimal

from django.db import transaction
from django.test import TestCase

from apps.catalog.models import Product
from apps.core.testing import LabAPITestCase, make_lab, make_member, make_product, make_variant, stock_in
from apps.inventory.models import StockMovement
from apps.inventory.services import StockLine, record_movement
from apps.labs.models import LabUser

MOVEMENTS = "/api/v1/inventory/movements/"


class WeightedAverageTests(TestCase):
    def setUp(self):
        self.lab = make_lab()

    def test_purchases_average_and_outgoing_keeps_average(self):
        frame = make_product(self.lab)
        stock_in(frame, 10, "1000")
        stock_in(frame, 10, "2000")
        self.assertEqual((frame.quantity, frame.average_cost), (20, Decimal("1500.00")))
        with transaction.atomic():
            damage = record_movement(
                lab=self.lab, line=StockLine(frame, None, 5), movement_type="damage"
            )
        frame.refresh_from_db()
        self.assertEqual((damage.qty, damage.unit_cost, damage.qty_after), (-5, Decimal("1500.00"), 15))
        self.assertEqual(frame.average_cost, Decimal("1500.00"))
        stock_in(frame, 5, "3500")
        self.assertEqual((frame.quantity, frame.average_cost), (20, Decimal("2000.00")))

    def test_average_resets_when_stock_was_empty(self):
        frame = make_product(self.lab)
        stock_in(frame, 1, "1000")
        with transaction.atomic():
            record_movement(lab=self.lab, line=StockLine(frame, None, 1), movement_type="damage")
        stock_in(frame, 2, "3000")
        self.assertEqual(frame.average_cost, Decimal("3000.00"))

    def test_rounding(self):
        frame = make_product(self.lab)
        stock_in(frame, 3, "1000")
        stock_in(frame, 4, "1001")
        self.assertEqual(frame.average_cost, Decimal("1000.57"))

    def test_variant_stock_rolls_up_to_product(self):
        lens = make_product(self.lab, "stock_lens")
        a, b = make_variant(lens, sph="-1"), make_variant(lens, sph="-2")
        stock_in(a, 4, "500")
        stock_in(b, 6, "700")
        lens.refresh_from_db()
        self.assertEqual(lens.quantity, 10)
        self.assertEqual((a.average_cost, b.average_cost), (Decimal("500.00"), Decimal("700.00")))


class StockApiTests(LabAPITestCase):
    def setUp(self):
        super().setUp()
        self.lab = make_lab()
        self.owner = make_member(self.lab, LabUser.Role.OWNER)
        self.staff = make_member(self.lab)
        self.login_as(self.owner)
        self.frame = make_product(self.lab, name="Frame")
        self.lens = make_product(self.lab, "stock_lens", name="Lens")
        self.variant = make_variant(self.lens, sph="-1.25")

    def _post(self, type_, lines, note=""):
        return self.client.post(MOVEMENTS, {"type": type_, "lines": lines, "note": note})

    def test_purchase_entry_with_many_lines(self):
        response = self._post("purchase", [
            {"product": self.frame.id, "qty": 5, "unit_cost": "40000"},
            {"variant": self.variant.id, "qty": 10, "unit_cost": "3000"},
        ], note="opening")
        self.assertEqual(response.status_code, 201, response.content)
        self.frame.refresh_from_db()
        self.variant.refresh_from_db()
        self.assertEqual((self.frame.quantity, self.frame.average_cost), (5, Decimal("40000.00")))
        self.assertEqual((self.variant.quantity, self.variant.average_cost), (10, Decimal("3000.00")))
        movement = StockMovement.objects.get(variant=self.variant)
        self.assertEqual((movement.product, movement.created_by, movement.reference_type), (self.lens, self.owner.user, "manual"))

    def test_entry_is_atomic(self):
        response = self._post("purchase", [
            {"product": self.frame.id, "qty": 5, "unit_cost": "40000"},
            {"product": self.lens.id, "qty": 1, "unit_cost": "1"},  # lens needs a variant
        ])
        self.assertEqual(response.json()["code"], "variant_required")
        self.frame.refresh_from_db()
        self.assertEqual(self.frame.quantity, 0)
        self.assertFalse(StockMovement.objects.exists())

    def test_rules(self):
        self.assertEqual(self._post("purchase", [{"product": self.frame.id, "qty": 1}]).json()["code"], "unit_cost_required")
        self.assertEqual(self._post("damage", [{"product": self.frame.id, "qty": 1}]).json()["code"], "insufficient_stock")
        service = make_product(self.lab, "service")
        self.assertEqual(self._post("adjustment", [{"product": service.id, "qty": 1}]).json()["code"], "not_stock_tracked")
        self.assertEqual(self._post("adjustment", [{"product": self.frame.id, "qty": 0}]).status_code, 400)
        other_variant = make_variant(make_product(self.lab, "stock_lens"))
        response = self._post("adjustment", [{"product": self.frame.id, "variant": other_variant.id, "qty": 1}])
        self.assertEqual(response.json()["code"], "variant_mismatch")

    def test_adjustment_signs_and_damage_is_negative(self):
        stock_in(self.frame, 10, "1000")
        self._post("adjustment", [{"product": self.frame.id, "qty": -3}])
        self._post("damage", [{"product": self.frame.id, "qty": 2}])
        self.frame.refresh_from_db()
        self.assertEqual(self.frame.quantity, 5)
        self.assertEqual(list(StockMovement.objects.order_by("id").values_list("qty", flat=True)), [10, -3, -2])

    def test_opening_adjustment_with_cost_sets_average(self):
        self._post("adjustment", [{"product": self.frame.id, "qty": 4, "unit_cost": "2500"}])
        self.frame.refresh_from_db()
        self.assertEqual(self.frame.average_cost, Decimal("2500.00"))

    def test_staff_cannot_post_movements(self):
        self.login_as(self.staff)
        response = self._post("adjustment", [{"product": self.frame.id, "qty": 1}])
        self.assertEqual(response.status_code, 403)

    def test_ledger_filters(self):
        stock_in(self.frame, 3)
        stock_in(self.variant, 2)
        self.assertEqual(self.client.get(MOVEMENTS, {"product": self.lens.id}).json()["count"], 1)
        self.assertEqual(self.client.get(MOVEMENTS, {"type": "purchase,sale"}).json()["count"], 2)

    def test_ledger_is_read_only(self):
        movement = stock_in(self.frame, 3)
        self.assertEqual(self.client.patch(f"{MOVEMENTS}{movement.id}/", {"qty": 100}).status_code, 405)
        self.assertEqual(self.client.delete(f"{MOVEMENTS}{movement.id}/").status_code, 405)

    def test_lab_isolation(self):
        other = make_lab()
        other_frame = make_product(other)
        other_movement = stock_in(other_frame, 4)
        self.assertEqual(self.client.get(MOVEMENTS).json()["count"], 0)
        self.assertEqual(self.client.get(f"{MOVEMENTS}{other_movement.id}/").status_code, 404)
        response = self._post("adjustment", [{"product": other_frame.id, "qty": 1, "unit_cost": "1"}])
        self.assertEqual(response.status_code, 400)
        other_frame.refresh_from_db()
        self.assertEqual(other_frame.quantity, 4)


class CostVisibilityTests(LabAPITestCase):
    """Staff without `can_view_costs` must never receive purchase prices or costs."""

    COST_KEYS = {"purchase_price", "average_cost", "unit_cost", "average_cost_after", "total_cost"}

    def setUp(self):
        super().setUp()
        self.lab = make_lab()
        self.owner = make_member(self.lab, LabUser.Role.OWNER)
        self.staff = make_member(self.lab)
        self.trusted = make_member(self.lab, can_view_costs=True)
        frame = make_product(self.lab, purchase_price="900", barcode="F1")
        stock_in(frame, 2, "1000")
        lens = make_product(self.lab, "stock_lens")
        variant = make_variant(lens, barcode="V1")
        stock_in(variant, 2, "500")
        self.urls = [
            "/api/v1/catalog/products/",
            f"/api/v1/catalog/products/{frame.id}/",
            f"/api/v1/catalog/products/{lens.id}/grid/",
            "/api/v1/catalog/variants/",
            f"/api/v1/catalog/variants/{variant.id}/",
            "/api/v1/catalog/lookup/?code=F1",
            "/api/v1/catalog/lookup/?code=V1",
            MOVEMENTS,
        ]

    def _keys(self, data):
        if isinstance(data, dict):
            for key, value in data.items():
                yield key
                yield from self._keys(value)
        elif isinstance(data, list):
            for item in data:
                yield from self._keys(item)

    def _leaked(self, member):
        self.login_as(member)
        leaked = set()
        for url in self.urls:
            response = self.client.get(url)
            self.assertEqual(response.status_code, 200, url)
            leaked |= self.COST_KEYS & set(self._keys(response.json()))
        return leaked

    def test_plain_staff_gets_no_costs(self):
        self.assertEqual(self._leaked(self.staff), set())

    def test_owner_and_trusted_staff_see_costs(self):
        self.assertTrue(self._leaked(self.owner))
        self.assertEqual(self._leaked(self.trusted), self._leaked(self.owner))

    def test_staff_cannot_order_by_cost(self):
        self.login_as(self.staff)
        response = self.client.get("/api/v1/catalog/products/", {"ordering": "average_cost"})
        self.assertEqual(response.status_code, 200)  # ignored, not an oracle
        ids = [r["id"] for r in response.json()["results"]]
        self.assertEqual(ids, list(Product.objects.filter(lab=self.lab).order_by("name", "id").values_list("id", flat=True)))
